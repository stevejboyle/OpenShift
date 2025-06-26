#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
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

# Define the VM folder name based on clusterName from YAML
CLUSTER_NAME="$(yq eval '.clusterName' "$CLUSTER_YAML")"
VM_FOLDER_NAME="${CLUSTER_NAME}" # e.g., ocp416

# Construct the full path for the VM folder within the datacenter.
# This assumes you want it directly under /<DatacenterName>/vm/
FULL_VCENTER_VM_FOLDER_PATH="/${VCENTER_DATACENTER}/vm/${VM_FOLDER_NAME}"

# Read the remote path for the RHCOS Live ISO from cluster YAML
RHCOS_LIVE_ISO_PATH_FROM_YAML="$(yq eval '.rhcos_live_iso_path' "$CLUSTER_YAML")"
# Construct the full remote path to the RHCOS live ISO in the datastore
RHCOS_REMOTE_ISO="/${GOVC_DATACENTER}/datastore/${GOVC_DATASTORE}/${RHCOS_LIVE_ISO_PATH_FROM_YAML}"

# Ensure VM folder exists
echo "🔍 Checking for VM folder: ${FULL_VCENTER_VM_FOLDER_PATH}..."
if ! govc folder.info "${FULL_VCENTER_VM_FOLDER_PATH}" &>/dev/null; then
  echo "📁 VM folder does not exist, creating: ${FULL_VCENTER_VM_FOLDER_PATH}"
  govc folder.create "${FULL_VCENTER_VM_FOLDER_PATH}"
else
  echo "✅ VM folder exists: ${FULL_VCENTER_VM_FOLDER_PATH}"
fi

NODES=(
  "bootstrap"
  "master-0"
  "master-1"
  "master-2"
  "worker-0"
  "worker-1"
)

echo "⏱ $(date '+%Y-%m-%d %H:%M:%S') - 🚀 Deploying VMs..."

for node in "${NODES[@]}"; do
  vm_name="${CLUSTER_NAME}-$node"
  ignition_file="$INSTALL_DIR/$node.ign" # Assuming INSTALL_DIR is set upstream (e.g., in rebuild-cluster.sh)
                                         # or within this script if needed, but it's relative here.

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
    "master-0"|"master-1"|"master-2")
      CPU=$(yq eval '.vm_sizing.master.cpu' "$CLUSTER_YAML")
      MEMORY_GB=$(yq eval '.vm_sizing.master.memory_gb' "$CLUSTER_YAML")
      DISK_GB=$(yq eval '.vm_sizing.master.disk_gb' "$CLUSTER_YAML")
      VM_MAC=$(yq eval ".node_macs.\"${node}\"" "$CLUSTER_YAML" || true)
      ;;
    "worker-0"|"worker-1") # Extend this logic for more workers as needed
      CPU=$(yq eval '.vm_sizing.worker.cpu' "$CLUSTER_YAML")
      MEMORY_GB=$(yq eval '.vm_sizing.worker.memory_gb' "$CLUSTER_YAML")
      DISK_GB=$(yq eval '.vm_sizing.worker.disk_gb' "$CLUSTER_YAML")
      VM_MAC=$(yq eval ".node_macs.\"${node}\"" "$CLUSTER_YAML" || true) # Optional: if workers also have pre-assigned MACs
      ;;
  esac

  echo "Creating VM: $vm_name with ${CPU} vCPUs, ${MEMORY_GB}GB RAM, ${DISK_GB}GB Disk."
  if [[ -n "$VM_MAC" ]]; then
    echo "   Assigning MAC: $VM_MAC"
  else
    echo "   MAC will be auto-assigned by vCenter."
  fi

  # Safely destroy VM if it exists
  govc vm.destroy -vm.ipath="${FULL_VCENTER_VM_FOLDER_PATH}/${vm_name}" 2>/dev/null || true

  # Build govc vm.create command dynamically with MAC if provided
  GOVC_CREATE_CMD=(
    govc vm.create
    -on=false
    -c="${CPU}" -m=$((MEMORY_GB * 1024))
    -g=rhel8_64Guest
    -net="$VCENTER_NETWORK"
    -disk.controller=lsilogic
    -disk="${DISK_GB}000"
    -iso="${RHCOS_REMOTE_ISO}"
    -pool="/$VCENTER_DATACENTER/host/$VCENTER_CLUSTER/Resources"
    -ds="$VCENTER_DATASTORE"
    -folder="${FULL_VCENTER_VM_FOLDER_PATH}"
  )

  # Add MAC address parameter if VM_MAC is not empty
  if [[ -n "$VM_MAC" ]]; then
    GOVC_CREATE_CMD+=("-net.mac=${VM_MAC}")
  fi

  GOVC_CREATE_CMD+=("$vm_name")

  # Execute the govc vm.create command
  "${GOVC_CREATE_CMD[@]}"

  # Inject Ignition data via guestinfo
  echo "Injecting ignition config via guestinfo for $vm_name..."
  govc vm.change -vm="$vm_name" -e "guestinfo.ignition.config.data.encoding=base64"
  govc vm.change -vm="$vm_name" -e "guestinfo.ignition.config.data=$(base64 -w0 "$ignition_file")"

  echo "Powering on: $vm_name"
  govc vm.power -on=true "$vm_name"
done

echo "✅ VM deployment complete!"
