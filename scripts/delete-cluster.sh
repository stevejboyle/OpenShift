#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPTS_DIR")"

CLUSTER_YAML="$1"

if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

CLUSTER_NAME=$(yq e '.clusterName' "$CLUSTER_YAML")
VCENTER_DATACENTER=$(yq e '.vcenter_datacenter' "$CLUSTER_YAML")
VM_FOLDER="/$VCENTER_DATACENTER/vm/OpenShift/$CLUSTER_NAME"

if ! command -v govc &> /dev/null; then
  echo "❌ govc CLI not found in PATH. Please install it and try again."
  exit 1
fi

source "$SCRIPTS_DIR/load-vcenter-env.sh"

if govc ls "$VM_FOLDER" &>/dev/null; then
  echo "🗑 Deleting VMs in folder: $VM_FOLDER"
  for VM in $(govc ls "$VM_FOLDER"); do
    echo "   - Destroying VM: $VM"
    govc vm.destroy "$VM" || echo "⚠️ Failed to destroy $VM (may already be gone)"
  done

  echo "🧹 Removing VM folder: $VM_FOLDER"
  govc object.destroy "$VM_FOLDER" || echo "⚠️ Failed to delete folder $VM_FOLDER"
else
  echo "ℹ️ No existing VM folder found at $VM_FOLDER (nothing to clean up)"
fi

echo "✅ Cluster VMs and folder removed (if they existed)"
