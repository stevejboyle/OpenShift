#!/usr/bin/env bash
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

# Get cluster configuration
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
VMN="$(yq '.vcenter_network' "$CLUSTER_YAML")"
# Use GOVC_FOLDER from environment
VMF="${GOVC_FOLDER}/${CLUSTER_NAME}"

# Import template if needed
TEMPLATE_NAME="rhcos-template-${CLUSTER_NAME}"
if ! govc ls "${VMF}/${TEMPLATE_NAME}" &>/dev/null; then
  echo "Importing RHCOS template..."
  # Ensure VM folder exists
  govc folder.create "${VMF}" || true
  govc import.ova -name "$TEMPLATE_NAME" -folder "$VMF" "$OVA"
  govc vm.markastemplate "${VMF}/${TEMPLATE_NAME}"
fi

# Define VMs to create (adjust based on your cluster needs)
VMS=("${CLUSTER_NAME}-bootstrap" "${CLUSTER_NAME}-master-0" "${CLUSTER_NAME}-master-1" "${CLUSTER_NAME}-master-2" "${CLUSTER_NAME}-worker-0" "${CLUSTER_NAME}-worker-1")

# Clone & configure
for vm in "${VMS[@]}"; do
  echo "🚀 Deploying $vm..."
  govc vm.clone -vm "${VMF}/${TEMPLATE_NAME}" -on=false -folder "$VMF" "$vm"
  
  # Configure network (may need to replace existing network)
  govc vm.network.change -vm "$vm" -net "$VMN" ethernet-0
  
  # Determine ignition file based on VM type
  if [[ "$vm" == *"bootstrap"* ]]; then
    ign="${BASE_DIR}/install-configs/${CLUSTER_NAME}/bootstrap.ign"
  elif [[ "$vm" == *"master"* ]]; then
    ign="${BASE_DIR}/install-configs/${CLUSTER_NAME}/master.ign"
  else
    ign="${BASE_DIR}/install-configs/${CLUSTER_NAME}/worker.ign"
  fi
  
  if [[ -f "$ign" ]]; then
    enc="$(base64 -w0 <"$ign")"
    govc vm.change -vm "$vm" -e "guestinfo.ignition.config.data.encoding=base64"
    govc vm.change -vm "$vm" -e "guestinfo.ignition.config.data=${enc}"
  else
    echo "⚠ Warning: Ignition file not found: $ign"
  fi

  govc vm.power -on "$vm"
done

echo "✅ All VMs deployed."
