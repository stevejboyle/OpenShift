#!/bin/zsh
set -e

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPTS="$(dirname "$0")"
source "${SCRIPTS}/load-vcenter-env.sh"
BASE_DIR="$(dirname "$SCRIPTS")"
OVA="${BASE_DIR}/assets/rhcos-4.16.36-x86_64-vmware.x86_64.ova"

VMF="$(yq '.vcenter_folder' "$CLUSTER_YAML")"
VMN="$(yq '.vcenter_network' "$CLUSTER_YAML")"

# Import template if needed
if ! govc ls "${VMF}/rhcos-template" &>/dev/null; then
  govc import.ova -name rhcos-template -folder "$VMF" "$OVA"
  govc vm.markastemplate "${VMF}/rhcos-template"
fi

# Clone & configure
for vm in $(yq -r '.vms|keys[]' "$CLUSTER_YAML"); do
  echo "🚀 Deploying $vm..."
  govc vm.clone -vm "${VMF}/rhcos-template" -on=false -folder "$VMF" "$vm"
  govc vm.network.add -vm "$vm" -net "$VMN" -net.adapter vmxnet3

  ign="${BASE_DIR}/install-configs/${vm}.ign"
  enc="$(base64 -w0 <"$ign")"

  govc vm.change -vm "$vm" -e "guestinfo.ignition.config.data.encoding=base64"
  govc vm.change -vm "$vm" -e "guestinfo.ignition.config.data=${enc}"

  govc vm.power -on "$vm"
done

echo "✅ All VMs deployed."
