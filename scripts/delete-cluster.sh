#!/bin/zsh
set -e

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/load-vcenter-env.sh"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

VMF="$(yq '.vcenter_folder' "$CLUSTER_YAML")"

echo "⚠ WARNING: This will delete all VMs AND generated configs for ${CLUSTER_YAML}"
echo "Type DELETE to confirm:"
read CONFIRM
if [[ "$CONFIRM" != "DELETE" ]]; then
  echo "Aborting."
  exit 1
fi

for vm in $(yq -r '.vms | keys[]' "$CLUSTER_YAML"); do
  path="${VMF}/${vm}"
  if govc vm.info "$path" &>/dev/null; then
    echo "🗑 Deleting $path..."
    govc vm.power -off -force "$path" || true
    govc vm.destroy "$path"      || true
  else
    echo "⚠ VM not found: $path"
  fi
done

# Remove all generated install-configs
rm -rf "${BASE_DIR}/install-configs"
echo "✅ Cluster VMs and generated files deleted."
