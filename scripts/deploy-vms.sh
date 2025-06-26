#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ ! -f "$CLUSTER_YAML" ]]; then
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
: "${VCENTER_FOLDER:=$(yq eval '.clusterName' "$CLUSTER_YAML")}"

INSTALL_DIR="install-configs/$(yq eval '.clusterName' "$CLUSTER_YAML")"
CLUSTER_NAME="$(yq eval '.clusterName' "$CLUSTER_YAML")"
RHCOS_LIVE_ISO_PATH_FROM_YAML="$(yq eval '.rhcos_live_iso_path' "$CLUSTER_YAML")"
RHCOS_REMOTE_ISO="/${GOVC_DATACENTER}/datastore/${GOVC_DATASTORE}/${RHCOS_LIVE_ISO_PATH_FROM_YAML}"


# Ensure VM folder exists
echo "🔍 Checking for VM folder: $VCENTER_FOLDER..."
if ! govc folder.info "$VCENTER_FOLDER" &>/dev/null; then
  echo "📁 VM folder does not exist, creating: $VCENTER_FOLDER"
  govc folder.create "$VCENTER_FOLDER"
else
  echo "✅ VM folder exists: $VCENTER_FOLDER"
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
  ignition_file="$INSTALL_DIR/$node.ign"

  # Determine sizing based on node type
  CPU=4
  MEMORY_GB=16
  DISK_GB=120
  VM_MAC="" # Initialize MAC variable

  if [[ "$node" == "bootstrap" ]]; then
    CPU=$(yq eval '.vm_sizing.bootstrap.cpu' "$CLUSTER_YAML")
    MEMORY_GB=$(yq eval '.vm_sizing.bootstrap.memory_gb' "$CLUSTER_YAML")
    DISK_GB=$(yq eval '.vm_sizing.bootstrap.disk_gb' "$CLUSTER_YAML")
    VM_MAC=$(yq eval ".node_macs.bootstrap" "$CLUSTER_YAML" || true)
  elif [[ "$node" == "master-0" ]]; then
    CPU=$(yq eval '.vm_sizing.master.cpu' "$CLUSTER_YAML")
    MEMORY_GB=$(yq eval '.vm_sizing.master.memory_gb' "$CLUSTER_YAML")
    DISK_GB=$(yq eval '.vm_sizing.master.disk_gb' "$CLUSTER_YAML")
    VM_MAC=$(yq eval ".node_macs.\"master-0\"" "$CLUSTER_YAML" || true)
  elif [[ "$node" == "master-1" ]]; then
    CPU=$(yq eval '.vm_sizing.master.cpu' "$CLUSTER_YAML")
    MEMORY_GB=$(yq eval '.vm_sizing.master.memory_gb' "$CLUSTER_YAML")
    DISK_GB=$(yq eval '.vm_sizing.master.disk_gb' "$CLUSTER_YAML")
    VM_MAC=$(yq eval ".node_macs.\"master-1\"" "$CLUSTER_YAML" || true)
  elif [[ "$node" == "master-2" ]]; then
    CPU=$(yq eval '.vm_sizing.master.cpu' "$CLUSTER_YAML")
    MEMORY_GB=$(yq eval '.vm_sizing.master.memory_gb' "$CLUSTER_YAML")
    DISK_GB=$(yq eval '.vm_sizing.master.disk_gb' "$CLUSTER_YAML")
    VM_MAC=$(yq eval ".node_macs.\"master-2\"" "$CLUSTER_YAML" || true)
  elif [[ "$node" == "worker-0" ]]; then
    CPU=$(yq eval '.vm_sizing.worker.cpu' "$CLUSTER_YAML")
    MEMORY_GB=$(yq eval '.vm_sizing.worker.memory_gb' "$CLUSTER_YAML")
    DISK_GB=$(yq eval('.vm_sizing.worker.disk_gb') "$CLUSTER_YAML")
    VM_MAC=$(yq eval ".node_macs.\"worker-0\"" "$CLUSTER_YAML" || true) # Optional: if workers also have pre-assigned MACs
  elif [[ "$node" == "worker-1" ]]; then
    CPU=$(yq eval '.vm_sizing.worker.cpu' "$CLUSTER_YAML")
    MEMORY_GB=$(yq eval('.vm_sizing.worker.memory_gb') "$CLUSTER_YAML")
    DISK_GB=$(yq eval('.vm_sizing.worker.disk_gb') "$CLUSTER_YAML")
    VM_MAC=$(yq eval ".node_macs.\"worker-1\"" "$CLUSTER_YAML" || true) # Optional: if workers also have pre-assigned MACs
  fi

  echo "Creating VM: $vm_name with ${CPU} vCPUs, ${MEMORY_GB}GB RAM, ${DISK_GB}GB Disk."
  if [[ -n "$VM_MAC" ]]; then
    echo "   Assigning MAC: $VM_MAC"
  else
    echo "   MAC will be auto-assigned by vCenter."
  fi

  # Safely destroy VM if it exists
  govc vm.destroy -vm.ipath="/$VCENTER_DATACENTER/vm/$VCENTER_FOLDER/$vm_name" 2>/dev/null || true

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
    -folder="$VCENTER_FOLDER"
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
