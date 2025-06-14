#!/usr/bin/env bash
set -e

CLUSTER_YAML="$(realpath "$1")"
if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "❌ Cluster file not found: $1"
  exit 1
fi

SCRIPTS="$(dirname "$0")"
source "${SCRIPTS}/load-vcenter-env.sh"

# NEW: Validate GOVC credentials work before proceeding
echo "🔍 Validating vSphere connectivity..."
if ! govc about &>/dev/null; then
  echo "❌ Cannot connect to vSphere. Check credentials and connectivity."
  echo "   URL: $GOVC_URL"
  echo "   User: $GOVC_USERNAME"
  echo "   Password: $([ -n "${GOVC_PASSWORD:-}" ] && echo "[SET]" || echo "[NOT SET]")"
  exit 1
fi
echo "✅ vSphere connectivity confirmed"

BASE_DIR="$(dirname "$SCRIPTS")"
OVA="${BASE_DIR}/assets/rhcos-4.16.36-x86_64-vmware.x86_64.ova"

# Get cluster configuration
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
VMN="$(yq '.vcenter_network' "$CLUSTER_YAML")"
# Use GOVC_FOLDER from environment for cluster VMs
VMF="${GOVC_FOLDER}/${CLUSTER_NAME}"

# Shared template configuration (can be overridden by environment variable)
TEMPLATE_PATH="${RHCOS_TEMPLATE_PATH:-/Lab/vm/OpenShift/rhcos-template}"

# Import template if needed (to shared location)
if ! govc ls "$TEMPLATE_PATH" &>/dev/null; then
  echo "Importing RHCOS template to shared location: $TEMPLATE_PATH..."
  # Ensure template folder exists
  TEMPLATE_FOLDER="$(dirname "$TEMPLATE_PATH")"
  TEMPLATE_NAME="$(basename "$TEMPLATE_PATH")"
  govc folder.create "$TEMPLATE_FOLDER" || true
  govc import.ova -name "$TEMPLATE_NAME" -folder "$TEMPLATE_FOLDER" "$OVA"
  govc vm.markastemplate "$TEMPLATE_PATH"
fi

# Define VMs to create (adjust based on your cluster needs)
VMS=("${CLUSTER_NAME}-bootstrap" "${CLUSTER_NAME}-master-0" "${CLUSTER_NAME}-master-1" "${CLUSTER_NAME}-master-2" "${CLUSTER_NAME}-worker-0" "${CLUSTER_NAME}-worker-1")

# Clone & configure
govc folder.create "$VMF" || true
for vm in "${VMS[@]}"; do
  echo "🚀 Deploying $vm..."
  govc vm.clone -vm "$TEMPLATE_PATH" -on=false -folder "$VMF" "$vm"
  
  # Configure network
  govc vm.network.change -vm "$vm" -net "$VMN" ethernet-0
  
  # Determine ignition file based on VM type  
  if [[ "$vm" == *"bootstrap"* ]]; then
    ign="${BASE_DIR}/install-configs/${CLUSTER_NAME}/bootstrap.ign"
  elif [[ "$vm" == *"master-0"* ]]; then
    ign="${BASE_DIR}/install-configs/${CLUSTER_NAME}/master-0.ign"
  elif [[ "$vm" == *"master-1"* ]]; then
    ign="${BASE_DIR}/install-configs/${CLUSTER_NAME}/master-1.ign" 
  elif [[ "$vm" == *"master-2"* ]]; then
    ign="${BASE_DIR}/install-configs/${CLUSTER_NAME}/master-2.ign"
  elif [[ "$vm" == *"worker-0"* ]]; then
    ign="${BASE_DIR}/install-configs/${CLUSTER_NAME}/worker-0.ign"
  elif [[ "$vm" == *"worker-1"* ]]; then
    ign="${BASE_DIR}/install-configs/${CLUSTER_NAME}/worker-1.ign"
  else
    ign="${BASE_DIR}/install-configs/${CLUSTER_NAME}/worker.ign"
  fi
  
  if [[ -f "$ign" ]]; then
    enc="$(base64 -w0 <"$ign")"
    govc vm.change -vm "$vm" -e "guestinfo.ignition.config.data.encoding=base64"
    govc vm.change -vm "$vm" -e "guestinfo.ignition.config.data=${enc}"
    echo "✅ Applied ignition config: $(basename "$ign")"
  else
    echo "⚠ Warning: Ignition file not found: $ign"
  fi

  govc vm.power -on "$vm"
done

echo "✅ All VMs deployed successfully with static IP configurations."