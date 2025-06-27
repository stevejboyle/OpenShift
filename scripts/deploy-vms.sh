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

  # --- FIX: Temporarily disable set -e to allow govc vm.create to run, then verify MAC ---
  set +e # Disable exit on error for this block
  echo "DEBUG: Executing govc vm.create command (expecting possible error message but successful creation):"
  govc vm.create "${GOVC_CREATE_OPTIONS[@]}" "$vm_name"
  CREATE_STATUS=$? # Capture the exit status of govc vm.create
  set -e # Re-enable exit on error

  if [[ "$CREATE_STATUS" -ne 0 ]]; then
      echo "❌ WARNING: govc vm.create returned non-zero exit code $CREATE_STATUS. Proceeding to verify MAC."
      # This is the expected "error" when -net.address is used but still created.
  fi

  # --- FIX: Verify MAC address immediately after creation ---
  if [[ -n "$VM_MAC" ]]; then
    echo "⚙️ Verifying MAC address for $vm_name post-creation..."
    # Give vCenter a brief moment to commit the changes if needed
    sleep 2
    ACTUAL_MAC=$(govc vm.info "$vm_name" -json | jq -r '.Config.Hardware.Device[] | select(.MacAddress != null and .Backing.DeviceName == "'"$VCENTER_NETWORK"'").MacAddress')
    if [[ "$ACTUAL_MAC" != "$VM_MAC" ]]; then
      echo "❌ ERROR: Assigned MAC ($VM_MAC) does NOT match actual VM MAC ($ACTUAL_MAC) after creation for $vm_name!"
      echo "   This implies govc vm.create -net.address failed to assign the MAC despite successful VM creation."
      exit 1
    fi
    echo "✅ MAC address verified: $ACTUAL_MAC for $vm_name."
  fi
  # --- END FIX ---

  # --- Inject ignition.url as a kernel argument using vm.change ---
  IGNITION_URL="http://${IGNITION_SERVER_IP}:${IGNITION_SERVER_PORT}/${ignition_url_path_segment}"
  echo "⚙️ Injecting Ignition URL as kernel argument for $vm_name: $IGNITION_URL"
  if ! govc vm.change "$vm_name" -e "guestinfo.kernel.args=ignition.url=$IGNITION_URL"; then
    echo "❌ Failed to set ignition.url kernel argument for $vm_name. Check govc permissions or VM state."
    exit 1
  fi
  echo "✅ Ignition URL kernel argument set."

  echo "Powering on: $vm_name"
  govc vm.power -on=true "$vm_name"
  echo "VM $vm_name powered on and will fetch Ignition config from $IGNITION_URL"
done

echo "✅ VM deployment complete!"
