#!/usr/bin/env bash
set -e

CLUSTER_YAML="$(realpath "$1")"
if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPTS="$(dirname "$0")"
source "${SCRIPTS}/load-vcenter-env.sh"
: "${GOVC_DATASTORE:?❌ GOVC_DATASTORE not set. Check govc.env.}"
DATASTORE="${GOVC_DATASTORE}"

# Validate vSphere connectivity
echo "🔍 Validating vSphere connectivity..."
if ! govc about &>/dev/null; then
  echo "❌ Cannot connect to vSphere. Check credentials and connectivity."
  exit 1
fi
echo "✅ vSphere connectivity confirmed"

BASE_DIR="$(dirname "$SCRIPTS")"
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
VMN="$(yq '.vcenter_network' "$CLUSTER_YAML")"
VMF="${GOVC_FOLDER}/${CLUSTER_NAME}"

# Read RHCOS ISO from YAML
RHCOS_ISO="$(yq -r '.rhcos_iso' "$CLUSTER_YAML")"
LOCAL_ISO="${BASE_DIR}/assets/${RHCOS_ISO}"
REMOTE_ISO_PATH="[${DATASTORE}] iso/rhcos/${RHCOS_ISO}"

# Define VMs
VMS=("${CLUSTER_NAME}-bootstrap" "${CLUSTER_NAME}-master-0" "${CLUSTER_NAME}-master-1" "${CLUSTER_NAME}-master-2" "${CLUSTER_NAME}-worker-0" "${CLUSTER_NAME}-worker-1")

govc folder.create "$VMF" || true
for vm in "${VMS[@]}"; do
  echo "🚀 Deploying $vm..."
  govc vm.create -m=8192 -c=4 -g=rhel9_64Guest -disk.controller=lsilogic -disk=12000 -net="$VMN" -on=false -folder="$VMF" "$vm"

  # Insert RHCOS ISO as primary boot device
  govc device.cdrom.add -vm="$vm"
  govc device.cdrom.insert -vm="$vm" "$REMOTE_ISO_PATH"

  # Insert ignition ISO (config)
  CONFIG_ISO="[${DATASTORE}] iso/${CLUSTER_NAME}/${vm}.iso"
  govc device.cdrom.add -vm="$vm"
  govc device.cdrom.insert -vm="$vm" "$CONFIG_ISO"

  # Set boot order
  CDROM_DEV="$(govc device.ls -vm "$vm" | grep -i 'cdrom' | head -n1)"
  govc device.boot -vm "$vm" -order "$CDROM_DEV"

  govc vm.power -on "$vm"
done

echo "✅ All VMs deployed via ISO successfully"
