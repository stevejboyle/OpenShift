#!/usr/bin/env bash
set -e

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/load-vcenter-env.sh"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Get cluster name and construct VM folder path
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
VMF="${GOVC_FOLDER}/${CLUSTER_NAME}"

echo "⚠ WARNING: This will delete all VMs AND generated configs for ${CLUSTER_NAME}"
echo "Type DELETE to confirm:"
read CONFIRM
if [[ "$CONFIRM" != "DELETE" ]]; then
  echo "Aborting."
  exit 1
fi

# Find and delete VMs in the cluster folder
if govc ls "$VMF" &>/dev/null; then
  for vm_path in $(govc find "$VMF" -type m); do
    vm_name=$(basename "$vm_path")
    echo "🗑 Deleting $vm_name..."
    govc vm.power -off -force "$vm_path" || true
    govc vm.destroy "$vm_path" || true
  done
  
  # Delete the template too
  template_path="${VMF}/rhcos-template-${CLUSTER_NAME}"
  if govc ls "$template_path" &>/dev/null; then
    echo "🗑 Deleting template..."
    govc vm.destroy "$template_path" || true
  fi
  
  # Remove the VM folder
  govc folder.destroy "$VMF" || true
else
  echo "⚠ VM folder not found: $VMF"
fi

# Remove cluster-specific generated install-configs
rm -rf "${BASE_DIR}/install-configs/${CLUSTER_NAME}"
echo "✅ Cluster VMs and generated files deleted."
