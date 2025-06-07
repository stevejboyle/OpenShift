#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/govc.env"

if ! command -v yq &>/dev/null; then
  echo "yq is required but not installed. Please run 'brew install yq'"
  exit 1
fi

VM_FILE="${SCRIPT_DIR}/cluster-vms.yaml"
CLUSTER_NAME=$(yq '.clusterName' "$VM_FILE")
BASE_DOMAIN=$(yq '.baseDomain' "$VM_FILE")
OVA_PATH="${SCRIPT_DIR}/rhcos-4.16.36-x86_64-vmware.x86_64.ova"

if ! govc ls "${GOVC_FOLDER}/rhcos-template" &>/dev/null; then
  echo "Importing RHCOS OVA..."
  govc import.ova -name rhcos-template -folder "$GOVC_FOLDER" "$OVA_PATH"
  govc vm.markastemplate "${GOVC_FOLDER}/rhcos-template"
else
  echo "✅ RHCOS template already exists."
fi

for VM in $(yq -r '.vms | keys[]' "$VM_FILE"); do
  IP=$(yq -r ".vms.${VM}.ip" "$VM_FILE")
  IGN=$(yq -r ".vms.${VM}.ign" "$VM_FILE")
  VMNAME="${VM}.${CLUSTER_NAME}.${BASE_DOMAIN}"

  echo "🚀 Deploying $VMNAME"

  govc vm.clone -vm "${GOVC_FOLDER}/rhcos-template" -on=false -folder "$GOVC_FOLDER" "$VMNAME"

  # Ensure NIC exists
  govc device.network.add -vm "$VMNAME" -net "$GOVC_NETWORK"

  # Confirm NIC reconfiguration
  govc vm.network.change -vm "$VMNAME" -net "$GOVC_NETWORK" ethernet-0 || true

  ENCODED_IGN=$(cat "${SCRIPT_DIR}/${IGN}" | base64 | tr -d '\n')
  govc vm.change -vm "$VMNAME" \
    -e "guestinfo.ignition.config.data=${ENCODED_IGN}" \
    -e "guestinfo.ignition.config.data.encoding=base64"

  govc vm.power.on "$VMNAME"
done

echo "✅ All VMs deployed successfully."
