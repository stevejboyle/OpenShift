#!/bin/bash
set -e

CLUSTER_FILE=$1
if [ -z "$CLUSTER_FILE" ]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
OVA_PATH="${BASE_DIR}/assets/rhcos-4.16.36-x86_64-vmware.x86_64.ova"
source "${BASE_DIR}/govc.env"

VM_FOLDER=$(yq '.vsphere.folder' "$CLUSTER_FILE")
VM_NETWORK=$(yq '.vsphere.network' "$CLUSTER_FILE")

if ! govc ls "${VM_FOLDER}/rhcos-template" &>/dev/null; then
  echo "Importing RHCOS OVA..."
  govc import.ova -name rhcos-template -folder "$VM_FOLDER" "$OVA_PATH"
  govc vm.markastemplate "${VM_FOLDER}/rhcos-template"
else
  echo "✅ RHCOS template already exists."
fi

for VM in $(yq -r '.vms | keys[]' "$CLUSTER_FILE"); do
  IGN="${BASE_DIR}/install-configs/${VM}.ign"
  VMNAME="${VM}"

  echo "🚀 Deploying $VMNAME"
  govc vm.clone -vm "${VM_FOLDER}/rhcos-template" -on=false -folder "$VM_FOLDER" "$VMNAME"
  govc vm.network.add -vm "$VMNAME" -net "$VM_NETWORK" -net.adapter vmxnet3

  ENCODED_IGN=$(base64 -w0 < "${IGN}")

  echo "Applying Ignition to VM: $VMNAME"
  echo "Payload length: ${#ENCODED_IGN} characters"

  govc vm.change -vm "$VMNAME" -e "guestinfo.ignition.config.data.encoding=base64"
  govc vm.change -vm "$VMNAME" -e "guestinfo.ignition.config.data=${ENCODED_IGN}"

  govc vm.power.on "$VMNAME"
done

echo "✅ All VMs deployed successfully."
