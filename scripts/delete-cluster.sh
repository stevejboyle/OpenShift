#!/usr/bin/env bash
set -e

# Parse arguments
FORCE_DELETE=false
CLUSTER_YAML=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--force)
      FORCE_DELETE=true
      shift
      ;;
    *)
      CLUSTER_YAML="$(realpath "$1")"
      shift
      ;;
  esac
done

if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 [-f|--force] <cluster.yaml>"
  echo "  -f, --force    Skip confirmation prompt"
  echo "❌ Cluster file not found: $1"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/load-vcenter-env.sh"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Get cluster name and construct VM folder path
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
VMF="${GOVC_FOLDER}/${CLUSTER_NAME}"

if [[ "$FORCE_DELETE" == "false" ]]; then
  echo "⚠ WARNING: This will delete all VMs AND generated configs for ${CLUSTER_NAME}"
  echo "Type DELETE to confirm:"
  read CONFIRM
  if [[ "$CONFIRM" != "DELETE" ]]; then
    echo "Aborting."
    exit 1
  fi
else
  echo "🗑 Force deleting cluster ${CLUSTER_NAME}..."
fi

# Find and delete VMs in the cluster folder
if govc ls "$VMF" &>/dev/null; then
  for vm_path in $(govc find "$VMF" -type m); do
    vm_name=$(basename "$vm_path")
    echo "🗑 Deleting $vm_name..."
    govc vm.power -off -force "$vm_path" || true
    govc vm.destroy "$vm_path" || true
  done
  
  # Remove the VM folder if it's empty after VM deletion
  if govc ls "$VMF" &>/dev/null; then
    # Check if folder is empty
    folder_contents="$(govc ls "$VMF" 2>/dev/null || true)"
    if [[ -z "$folder_contents" ]]; then
      echo "🗑 Removing empty VM folder..."
      govc object.destroy "$VMF" || true
    else
      echo "⚠ VM folder not empty, leaving: $VMF"
    fi
  fi
else
  echo "⚠ VM folder not found: $VMF"
fi

# Don't delete shared template - it's reusable across clusters
# The template at /Lab/vm/OpenShift/rhcos-template is shared and should be preserved

# Remove cluster-specific generated install-configs
rm -rf "${BASE_DIR}/install-configs/${CLUSTER_NAME}"
echo "✅ Cluster VMs and generated files deleted."
