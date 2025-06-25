#!/usr/bin/env bash

set -euo pipefail

CLUSTER_YAML="$1"
if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

# Load environment variables and validate
source "$(dirname "$0")/load-vcenter-env.sh" "$CLUSTER_YAML"

# Fallback logic: populate VCENTER_* from GOVC_* if not already set
: "${VCENTER_NETWORK:=${GOVC_NETWORK}}"
: "${VCENTER_DATASTORE:=${GOVC_DATASTORE}}"
: "${VCENTER_CLUSTER:=${GOVC_CLUSTER}}"
: "${VCENTER_DATACENTER:=${GOVC_DATACENTER}}"
: "${VCENTER_FOLDER:=$(basename "$CLUSTER_YAML" .yaml)}"

INSTALL_DIR="install-configs/$(basename "$CLUSTER_YAML" .yaml)"

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
  vm_name="$(basename "$CLUSTER_YAML" .yaml)-$node"
  ignition_file="$INSTALL_DIR/$node.ign"
  echo "Creating VM: $vm_name"

  govc vm.destroy -vm.ipath="/$VCENTER_DATACENTER/vm/$VCENTER_FOLDER/$vm_name" 2>/dev/null || true

  govc vm.create \
    -on=false \
    -c=4 -m=16384 \
    -g=rhel8_64Guest \
    -net="$VCENTER_NETWORK" \
    -disk.controller=lsilogic \
    -disk=12000 \
    -iso="${vm_name}.iso" \
    -pool="/$VCENTER_DATACENTER/host/$VCENTER_CLUSTER/Resources" \
    -ds="$VCENTER_DATASTORE" \
    -folder="$VCENTER_FOLDER" \
    "$vm_name"

  govc vm.change -vm="$vm_name" -e "guestinfo.ignition.config.data.encoding=base64"
  govc vm.change -vm="$vm_name" -e "guestinfo.ignition.config.data=$(base64 -w0 "$ignition_file")"

  echo "Powering on: $vm_name"
  govc vm.power -on=true "$vm_name"
done

echo "✅ VM deployment complete!"
