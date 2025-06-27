#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
INSTALL_DIR="$2" # Capture INSTALL_DIR as the second argument

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
: "${GOVC_FOLDER:=/}" # Default to root if not set in govc.env, though it should be set.

# Define the VM folder name based on clusterName from YAML
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
VM_CLUSTER_FOLDER_NAME="${CLUSTER_NAME}" # e.g., ocp416

# Construct the full path for the cluster's VM folder based on GOVC_FOLDER
FULL_VCENTER_VM_FOLDER_PATH="${GOVC_FOLDER}/${VM_CLUSTER_FOLDER_NAME}"

# Read the remote path for the RHCOS Live ISO from cluster YAML
RHCOS_LIVE_ISO_RELATIVE_PATH="$(yq '.rhcos_live_iso_path' "$CLUSTER_YAML")"
RHCOS_REMOTE_ISO="[${VCENTER_DATASTORE}] ${RHCOS_LIVE_ISO_RELATIVE_PATH}"

# Read Ignition Server details directly within deploy-vms.sh
IGNITION_SERVER_IP=$(yq '.ignition_server.host_ip' "$CLUSTER_YAML" || { echo "❌ Failed to read ignition_server.host_ip from $CLUSTER_YAML"; exit 1; })
IGNITION_SERVER_PORT=$(yq '.ignition_server.port' "$CLUSTER_YAML" || { echo "❌ Failed to read ignition_server.port from $CLUSTER_YAML"; exit 1; })

# Ensure VM folder exists
echo "🔍 Checking for VM folder: ${FULL_VCENTER_VM_FOLDER_PATH}..."
if ! govc folder.info "${FULL_VCENTER_VM_FOLDER_PATH}" &>/dev/null; then
  echo "📁 VM folder does not exist, creating: ${FULL_VCENTER_VM_FOLDER_PATH}"
  govc folder.create "${FULL_VCENTER_VM_FOLDER_PATH}"
else
  echo "✅ VM folder exists: ${FULL_VCENTER_VM_FOLDER_PATH}"
fi

# Dynamically build NODES array from cluster YAML
MASTER_REPLICAS=$(yq '.node_counts.master' "$CLUSTER_YAML")
WORKER_REPLICAS=$(yq '.node_counts.worker' "$CLUSTER_YAML")

NODES=("bootstrap") # Bootstrap node is always present

for i in $(seq 0 $((MASTER_REPLICAS - 1))); do
  NODES+=("master-${i}")
done

for i in $(seq 0 $((WORKER_REPLICAS - 1))); do
  NODES+=("worker-${i}")
done

echo "VMs to deploy: ${NODES[@]}"

echo "⏱ $(date '+%Y-%m-%d %H:%M:%S') - 🚀 Deploying VMs..."

for node in "${NODES[@]}"; do
  vm_name="${CLUSTER_NAME}-$node"

  # Determine the correct ignition file path (local on host) based on node type
  case "$node" in
    "bootstrap")
      ignition_file_local="$INSTALL_DIR/bootstrap.ign"
      ignition_url_path_segment="bootstrap.ign" # Will be at root of webserver
      ;;
    "master-"*)
      ignition_file_local="$INSTALL_DIR/master.ign"
      ignition_url_path_segment="master.ign"      # Will be at root of webserver
      ;;
    "worker-"*)
      ignition_file_local="$INSTALL_DIR/worker.ign"
      ignition_url_path_segment="worker.ign"      # Will be at root of webserver
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
      CPU=$(yq '.vm_sizing.bootstrap.cpu' "$CLUSTER_YAML")
      MEMORY_GB=$(yq '.vm_sizing.bootstrap.memory_gb' "$CLUSTER_YAML")
      DISK_GB=$(yq '.vm_sizing.bootstrap.disk_gb' "$CLUSTER_YAML")
      VM_MAC=$(yq ".node_macs.bootstrap" "$CLUSTER_YAML" || true)
      ;;
    "master-"*)
      CPU=$(yq '.vm_sizing.master.cpu' "$CLUSTER_YAML")
      MEMORY_GB=$(yq '.vm_sizing.master.memory_gb' "$CLUSTER_YAML")
      DISK_GB=$(yq '.vm_sizing.master.disk_gb' "$CLUSTER_YAML")
      VM_MAC=$(yq ".node_macs.\"${node}\"" "$CLUSTER_YAML" || true)
      ;;
    "worker-"*)
      CPU=$(yq '.vm_sizing.worker.cpu' "$CLUSTER_YAML")
      MEMORY_GB=$(yq '.vm_sizing.worker.memory_gb' "$CLUSTER_YAML")
      DISK_GB=$(yq '.vm_sizing.worker.disk_gb' "$CLUSTER_YAML")
      VM_MAC=$(yq ".node_macs.\"${node}\"" "$CLUSTER_YAML" || true)
      ;;
    *)
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

  # Build govc vm.create command options
  GOVC_CREATE_OPTIONS=(
    -on=false # Create powered off
    -c="${CPU}" -m=$((MEMORY_GB * 1024))
    -g=rhel8_64Guest
    -net="$VCENTER_NETWORK" # Specify network name
    -disk.controller=lsilogic
    -disk="${DISK_GB}000"
    -iso="${RHCOS_REMOTE_ISO}"
    -pool="/$VCENTER_DATACENTER/host/$VCENTER_CLUSTER/Resources"
    -ds="$VCENTER_DATASTORE"
    -folder="${FULL_VCENTER_VM_FOLDER_PATH}"
  )

  # Conditionally add -net.address flag here, before the VM name
  if [[ -n "$VM_MAC" ]]; then
    GOVC_CREATE_OPTIONS+=("-net.address")
    GOVC_CREATE_OPTIONS+=("${VM_MAC}")
  fi

  # --- FIX: Temporarily disable set -e to allow govc vm.create to run, then verify creation.
  # Removed MAC verification block as per user's request, assuming it works.
  set +e # Disable exit on error for this block
  echo "DEBUG: Executing govc vm.create command and capturing output:"
  FULL_GOVC_CREATE_OUTPUT=$(govc vm.create "${GOVC_CREATE_OPTIONS[@]}" "$vm_name" 2>&1)
  CREATE_STATUS=$? # Capture the exit status of govc vm.create
  set -e # Re-enable exit on error

  if [[ "$CREATE_STATUS" -ne 0 ]]; then
      echo "❌ FATAL ERROR: govc vm.create returned non-zero exit code $CREATE_STATUS."
      echo "Full govc vm.create output:"
      echo "$FULL_GOVC_CREATE_OUTPUT"
      exit 1 # Exit script because VM creation is essential.
  else
      echo "✅ govc vm.create completed successfully. Output:"
      echo "$FULL_GOVC_CREATE_OUTPUT" # Print govc's actual output to logs
  fi
  # --- END FIX ---

  # --- REMOVED: MAC Address Verification Block ---
  # This block was removed as per user's request, assuming MAC assignment works.
  # --- END REMOVED ---

  # --- Inject ignition.url as a kernel argument using vm.change ---
  IGNITION_URL="http://${IGNITION_SERVER_IP}:${IGNITION_SERVER_PORT}/${ignition_url_path_segment}" #
  KERNEL_ARGS="ignition.url=$IGNITION_URL rd.neednet=1 ip=dhcp coreos.platform=vsphere console=ttyS0,115200 ignition.debug" # Final set of kernel args
  echo "⚙️ Injecting Ignition URL as kernel argument for $vm_name: $KERNEL_ARGS"
  if ! govc vm.change -vm "$vm_name" -e "guestinfo.kernel.args=$KERNEL_ARGS"; then #
    echo "❌ Failed to set ignition.url kernel argument for $vm_name. Check govc permissions or VM state."
    exit 1
  fi
  echo "✅ Ignition URL kernel argument set."

  echo "Powering on: $vm_name"
  govc vm.power -on=true "$vm_name"
  echo "VM $vm_name powered on and will fetch Ignition config from $IGNITION_URL"
done

echo "✅ VM deployment complete!"
