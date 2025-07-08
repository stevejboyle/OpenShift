#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
INSTALL_DIR="${2:-install-configs/$(basename "$CLUSTER_YAML" .yaml)}"

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
VM_CLUSTER_FOLDER_NAME="${CLUSTER_NAME}" 

# Construct the full path for the cluster's VM folder based on GOVC_FOLDER
FULL_VCENTER_VM_FOLDER_PATH="${GOVC_FOLDER}/${VM_CLUSTER_FOLDER_NAME}"

# --- NEW: Read RHCOS VM Template path from cluster YAML ---
RHCOS_VM_TEMPLATE_PATH=$(yq '.rhcos_vm_template' "$CLUSTER_YAML" || { echo "❌ Failed to read rhcos_vm_template from $CLUSTER_YAML"; exit 1; })
# --- END NEW ---

# Read Ignition Server details (used for logging only now, not for actual fetching URL)
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
      ignition_file_local="$INSTALL_DIR/bootstrap.ign" # Local file to base64 encode
      ;;
    "master-"*)
      # Use individual master ignition files with network config
      ignition_file_local="$INSTALL_DIR/${node}.ign"   # e.g., master-0.ign, master-1.ign
      ;;
    "worker-"*)
      # Use individual worker ignition files with network config  
      ignition_file_local="$INSTALL_DIR/${node}.ign"   # e.g., worker-0.ign, worker-1.ign
      ;;
    *)
      echo "❌ Unknown node type: $node. Cannot determine ignition file."
      exit 1
      ;;
  esac

  # Verify the ignition file exists
  if [[ ! -f "$ignition_file_local" ]]; then
    echo "❌ ERROR: Ignition file not found: $ignition_file_local"
    echo "   Make sure to run the network configuration scripts first"
    exit 1
  fi

  echo "Creating VM: $vm_name with ${CPU} vCPUs, ${MEMORY_GB}GB RAM, ${DISK_GB}GB Disk."
  if [[ -n "$VM_MAC" ]]; then
    echo "   Desired MAC: $VM_MAC"
  else
    echo "   MAC will be auto-assigned by vCenter."
  fi

  # Safely destroy VM if it exists, using the full path
  govc vm.destroy -vm.ipath="${FULL_VCENTER_VM_FOLDER_PATH}/${vm_name}" 2>/dev/null || true

  # --- FIX: Use govc vm.clone instead of vm.create ---
  GOVC_CLONE_OPTIONS=(
    -vm="$RHCOS_VM_TEMPLATE_PATH" # Source template VM
    -net="$VCENTER_NETWORK" # Network for the cloned VM
    -ds="$VCENTER_DATASTORE"
    -cluster="$VCENTER_CLUSTER"
    -folder="${FULL_VCENTER_VM_FOLDER_PATH}"
    -on=false # Clone, but keep powered off
    -c="${CPU}" -m=$((MEMORY_GB * 1024)) # Apply CPU/Memory sizing
  )

  # Conditionally add -net.mac and -net.mac.type flags for cloning
  if [[ -n "$VM_MAC" ]]; then
    GOVC_CLONE_OPTIONS+=("-net.address=${VM_MAC}")
  fi

  set +e # Disable exit on error for this block
  echo "DEBUG: Executing govc vm.clone command and capturing output:"
  FULL_GOVC_CLONE_OUTPUT=$(govc vm.clone "${GOVC_CLONE_OPTIONS[@]}" "$vm_name" 2>&1)
  CLONE_STATUS=$? # Capture the exit status of govc vm.clone
  set -e # Re-enable exit on error

  if [[ "$CLONE_STATUS" -ne 0 ]]; then
      echo "❌ FATAL ERROR: govc vm.clone returned non-zero exit code $CLONE_STATUS."
      echo "Full govc vm.clone output:"
      echo "$FULL_GOVC_CLONE_OUTPUT"
      exit 1 # Exit script because VM cloning is essential.
  else
      echo "✅ govc vm.clone completed successfully. Output:"
      echo "$FULL_GOVC_CLONE_OUTPUT" # Print govc's actual output to logs
  fi
  # --- END FIX ---

  echo "⚙️ Skipping MAC address verification as vm.clone is expected to handle it."

  # --- FIX: Resize Disk After Cloning ---
  # Assuming the primary disk is 'Hard disk 1' and needs to be resized to DISK_GB
  echo "⚙️ Resizing disk for $vm_name to ${DISK_GB}GB..."
  # The disk size is set in GB, govc vm.disk.change expects it in GB
  if ! govc vm.disk.change -vm "$vm_name" -disk.label="Hard disk 1" -size="${DISK_GB}GB"; then
    echo "❌ Failed to resize disk for $vm_name. Check govc permissions or VM state."
    exit 1
  fi
  echo "✅ Disk resized to ${DISK_GB}GB for $vm_name."
  sleep 5 # Give vCenter time to commit disk resize
  # --- END FIX ---

  # --- NEW FIX: Inject Ignition Config Data (Base64) ---
  # This is the method the user confirmed works for modern RedHat versions.
  # It bypasses kernel args and web server fetching issues.
  IGNITION_CONFIG_B64=$(base64 -i "$ignition_file_local" | tr -d '\n')
  KERNEL_ARGS="console=ttyS0,115200 ignition.debug coreos.platform=vsphere cgroup_no_v1=all systemd.unified_cgroup_hierarchy=1 swapaccount=1 noswap"

  #--- DEBUG: Verify ignition_file_local ---
  echo "DEBUG: Checking local ignition file: $ignition_file_local"
  if [[ ! -f "$ignition_file_local" ]]; then
    echo "❌ ERROR: Local ignition file not found: $ignition_file_local"
    exit 1
  fi
  LOCAL_IGN_SIZE=$(stat -f %z "$ignition_file_local" 2>/dev/null || stat -c %s "$ignition_file_local" 2>/dev/null)
  echo "DEBUG: Local ignition file size: $LOCAL_IGN_SIZE bytes"
 
  # FIX: Force base64 to read from stdin, redirect stderr to /dev/null, check status
  set +e # Disable exit on error for base64
  # Use 'cat "$ignition_file_local"' instead of 'base64 -i' for robustness.
  IGNITION_CONFIG_B64=$(cat "$ignition_file_local" | base64 -w0 2>/dev/null | tr -d '\n') # Using -w0 for GNU base64
  BASE64_STATUS=$? # Capture base64 exit status
  set -e # Re-enable exit on error
 
  if [[ $BASE64_STATUS -ne 0 ]]; then
      echo "❌ ERROR: base64 encoding of $ignition_file_local failed with exit code $BASE64_STATUS. Aborting."
      exit 1
  fi

  echo "⚙️ Injecting Ignition config data (base64) for $vm_name. Size: ${#IGNITION_CONFIG_B64} bytes."
  if ! govc vm.change -vm "$vm_name" \
    -e "guestinfo.ignition.config.data=${IGNITION_CONFIG_B64}" \
    -e "guestinfo.ignition.config.data.encoding=base64" \
    -e "guestinfo.kernel.args=${KERNEL_ARGS}"; then
    echo "❌ Failed to set guestinfo.ignition.config.data for $vm_name. Check govc permissions or VM state."
    # If the error is due to size limit, this will fail.
    exit 1
  fi
  echo "✅ guestinfo.ignition.config.data set."
  # --- END NEW FIX ---

  echo "Powering on: $vm_name"
  govc vm.power -on=true "$vm_name"
  echo "VM $vm_name powered on and will boot with Ignition config from guestinfo."
done

echo "✅ VM deployment complete!"
