#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
INSTALL_DIR="$2" # Capture the second argument as INSTALL_DIR

if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

if [[ -z "$INSTALL_DIR" ]]; then
  echo "❌ INSTALL_DIR not provided. Usage: $0 <cluster-yaml> <install-dir>"
  exit 1
fi

SCRIPTS_DIR="$(dirname "$0")"

# Load environment variables and validate
source "${SCRIPTS_DIR}/load-vcenter-env.sh" "$CLUSTER_YAML"

# Fallback logic: populate VCENTER_* from GOVC_* if not already set
: "${VCENTER_NETWORK:=${GOVC_NETWORK}}"
: "${VCENTER_DATASTORE:=${GOVC_DATASTORE}}"
: "${VCENTER_CLUSTER:=${GOVC_CLUSTER}}"
: "${VCENTER_DATACENTER:=${GOVC_DATACENTER}}"
# Use GOVC_FOLDER as the base for VM folder path
: "${GOVC_FOLDER:=/}" # Default to root if not set in govc.env, though it should be set.

# Define the VM folder name based on clusterName from YAML
CLUSTER_NAME="$(yq eval '.clusterName' "$CLUSTER_YAML")"
VM_CLUSTER_FOLDER_NAME="${CLUSTER_NAME}" # e.g., ocp416

# Construct the full path for the cluster's VM folder based on GOVC_FOLDER
# Example: /Lab/vm/OpenShift/ocp416
FULL_VCENTER_VM_FOLDER_PATH="${GOVC_FOLDER}/${VM_CLUSTER_FOLDER_NAME}"

# Read the remote path for the RHCOS Live ISO from cluster YAML
# This should be the path *relative to the datastore root* (e.g., 'iso/mycluster-rhcos-live.iso')
RHCOS_LIVE_ISO_RELATIVE_PATH="$(yq eval '.rhcos_live_iso_path' "$CLUSTER_YAML")"
# Construct the full remote path to the RHCOS live ISO in the datastore,
# in the format govc expects for files *within* a datastore.
# Example: '[datastore-SAN1] iso/ocp416-rhcos-live.iso'
RHCOS_REMOTE_ISO="[${VCENTER_DATASTORE}] ${RHCOS_LIVE_ISO_RELATIVE_PATH}"

# Ensure VM folder exists
echo "🔍 Checking for VM folder: ${FULL_VCENTER_VM_FOLDER_PATH}..."
# govc folder.info expects an absolute path
if ! govc folder.info "${FULL_VCENTER_VM_FOLDER_PATH}" &>/dev/null; then
  echo "📁 VM folder does not exist, creating: ${FULL_VCENTER_VM_FOLDER_PATH}"
  # govc folder.create expects an absolute path or path relative to current context
  # Providing full path ensures it's created correctly under the specified GOVC_FOLDER base.
  govc folder.create "${FULL_VCENTER_VM_FOLDER_PATH}"
else
  echo "✅ VM folder exists: ${FULL_VCENTER_VM_FOLDER_PATH}"
fi

# --- NEW: Dynamically build NODES array from cluster YAML ---
MASTER_REPLICAS=$(yq eval '.node_counts.master' "$CLUSTER_YAML")
WORKER_REPLICAS=$(yq eval '.node_counts.worker' "$CLUSTER_YAML")

NODES=("bootstrap") # Bootstrap node is always present

for i in $(seq 0 $((MASTER_REPLICAS - 1))); do
  NODES+=("master-${i}")
done

for i in $(seq 0 $((WORKER_REPLICAS - 1))); do
  NODES+=("worker-${i}")
done

echo "VMs to deploy: ${NODES[@]}"
# --- END NEW NODE BUILD ---

echo "⏱ $(date '+%Y-%m-%d %H:%M:%S') - 🚀 Deploying VMs..."

for node in "${NODES[@]}"; do
  vm_name="${CLUSTER_NAME}-$node"

  # Determine the correct ignition file path based on node type
  case "$node" in
    "bootstrap")
      ignition_file="$INSTALL_DIR/bootstrap.ign"
      ;;
    "master-"*) # Matches master-0, master-1, etc.
      ignition_file="$INSTALL_DIR/master.ign" # All master nodes use the same master.ign
      ;;
    "worker-"*) # Matches worker-0, worker-1, etc.
      ignition_file="$INSTALL_DIR/worker.ign" # All worker nodes use the same worker.ign
      ;;
    *)
      echo "❌ Unknown node type: $node. Cannot determine ignition file."
      exit 1
      ;;
  esac

  # Determine sizing based on node type
  CPU=4
  MEMORY_GB=16
  DISK_GB=120
  VM_MAC="" # Initialize MAC variable

  case "$node" in
    "bootstrap")
      CPU=$(yq eval '.vm_sizing.bootstrap.cpu' "$CLUSTER_YAML")
      MEMORY_GB=$(yq eval '.vm_sizing.bootstrap.memory_gb' "$CLUSTER_YAML")
      DISK_GB=$(yq eval '.vm_sizing.bootstrap.disk_gb' "$CLUSTER_YAML")
      VM_MAC=$(yq eval ".node_macs.bootstrap" "$CLUSTER_YAML" || true)
      ;;
    "master-"*) # Matches master-0, master-1, etc.
      CPU=$(yq eval '.vm_sizing.master.cpu' "$CLUSTER_YAML")
      MEMORY_GB=$(yq eval '.vm_sizing.master.memory_gb' "$CLUSTER_YAML")
      DISK_GB=$(yq eval '.vm_sizing.master.disk_gb' "$CLUSTER_YAML")
      # Dynamically pull MAC for specific master (e.g., node_macs.master-0)
      VM_MAC=$(yq eval ".node_macs.\"${node}\"" "$CLUSTER_YAML" || true)
      ;;
    "worker-"*) # Matches worker-0, worker-1, etc.
      CPU=$(yq eval '.vm_sizing.worker.cpu' "$CLUSTER_YAML")
      MEMORY_GB=$(yq eval('.vm_sizing.worker.memory_gb') "$CLUSTER_YAML")
      DISK_GB=$(yq eval('.vm_sizing.worker.disk_gb') "$CLUSTER_YAML")
      # Dynamically pull MAC for specific worker (e.g., node_macs.worker-0)
      VM_MAC=$(yq eval ".node_macs.\"${node}\"" "$CLUSTER_YAML" || true)
      ;;
    *)
      # Fallback or error if an unhandled node type somehow reaches here (shouldn't with above NODES array)
      echo "❌ Error: Sizing/MAC not defined for node type: $node"
      exit 1
      ;;
  esac

  echo "Creating VM: $vm_name with ${CPU} vCPUs, ${MEMORY_GB}GB RAM, ${DISK_GB}GB Disk."
  if [[ -n "$VM_MAC" ]]; then
    echo "   Desired MAC: $VM_MAC"
  else
    echo "   MAC will be auto-assigned by vCenter."
  fi

  # Safely destroy VM if it exists, using the full VM path
  govc vm.destroy -vm.ipath="${FULL_VCENTER_VM_FOLDER_PATH}/${vm_name}" 2>/dev/null || true

  # Build govc vm.create command
  GOVC_CREATE_CMD=(
    govc vm.create
    -on=false # Create powered off to ensure MAC assignment can happen cleanly
    -c="${CPU}" -m=$((MEMORY_GB * 1024))
    -g=rhel8_64Guest
    -net="$VCENTER_NETWORK" # Specify network name ONLY
    -disk.controller=lsilogic
    -disk="${DISK_GB}000"
    -iso="${RHCOS_REMOTE_ISO}"
    -pool="/$VCENTER_DATACENTER/host/$VCENTER_CLUSTER/Resources"
    -ds="$VCENTER_DATASTORE"
    -folder="${FULL_VCENTER_VM_FOLDER_PATH}"
    "$vm_name" # Append VM name last
  )

  # Execute the govc vm.create command
  "${GOVC_CREATE_CMD[@]}"

  # --- STEPS FOR MAC ASSIGNMENT ---
  # If VM_MAC is specified, the VM must be powered off to change the MAC address.
  # We created with -on=false, so the VM is already in the correct state for vm.change.
  if [[ -n "$VM_MAC" ]]; then
    echo "⚙️ Setting specific MAC address for $vm_name to $VM_MAC..."
    # Change the MAC address of the first network adapter (ethernet0)
    if ! govc vm.change -vm "$vm_name" -e "ethernet0.macAddress=${VM_MAC}"; then
      echo "❌ Failed to set MAC address for $vm_name. Please check govc permissions or VM state."
      exit 1
    fi
    echo "✅ MAC address set to $VM_MAC for $vm_name."
  fi
  # --- END MAC ASSIGNMENT STEPS ---

  # No guestinfo injection here; VMs will fetch via HTTP

  echo "Powering on: $vm_name"
  govc vm.power -on=true "$vm_name"
  echo "VM $vm_name powered on and will fetch Ignition config from http://${IGNITION_SERVER_IP}:${IGNITION_SERVER_PORT}/${CLUSTER_NAME}/${node}.ign"
  # Note: The 'bootstrap.ign', 'master.ign', and 'worker.ign' files will be served by HTTP server.
  # The 'node.ign' placeholder here is a general indicator of the expected fetch path.
done

echo "✅ VM deployment complete!"