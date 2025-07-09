#!/usr/bin/env bash
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPTS")"

# Load vCenter environment variables
source "$SCRIPTS/load-vcenter-env.sh"

CLUSTER_YAML="$1"

if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

CLUSTER_NAME=$(yq e '.clusterName' "$CLUSTER_YAML")
VCENTER_DATACENTER=$(yq e '.vcenter_datacenter' "$CLUSTER_YAML")

# Check if custom folder is defined; if not, use fallback
VCENTER_FOLDER=$(yq e '.vcenter_folder // ""' "$CLUSTER_YAML")
if [[ -z "$VCENTER_FOLDER" || "$VCENTER_FOLDER" == "null" ]]; then
  VCENTER_FOLDER="/$VCENTER_DATACENTER/vm/OpenShift/$CLUSTER_NAME"
fi

echo "🧹 Looking for VMs in folder: $VCENTER_FOLDER"

# Find all VMs under the folder
VM_PATHS=$(govc find "$VCENTER_FOLDER" -type m || true)

if [[ -z "$VM_PATHS" ]]; then
  echo "⚠️  No VMs found under folder: $VCENTER_FOLDER"
else
  echo "🗑️  Deleting VMs:"
  echo "$VM_PATHS"
  while read -r vm; do
    govc vm.destroy "$vm" || echo "⚠️ Failed to destroy VM: $vm"
  done <<< "$VM_PATHS"
fi

echo "🧼 Attempting to delete VM folder (if empty): $VCENTER_FOLDER"
govc object.destroy "$VCENTER_FOLDER" || echo "⚠️ Skipped folder deletion (likely not empty or in use)"

INSTALL_DIR="$BASE_DIR/install-configs/$CLUSTER_NAME"
if [[ -d "$INSTALL_DIR" ]]; then
  echo "🗑️  Deleting install-configs directory: $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
else
  echo "ℹ️  No install-configs directory found for $CLUSTER_NAME"
fi

echo "✅ Cluster cleanup complete for: $CLUSTER_NAME"
