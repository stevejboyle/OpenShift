#!/usr/bin/env bash
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPTS")"

CLUSTER_YAML="$1"

if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

# Load values from cluster YAML
CLUSTER_NAME=$(yq e '.clusterName' "$CLUSTER_YAML")
VM_FOLDER=$(yq e '.vcenter_folder' "$CLUSTER_YAML")
VM_FOLDER="${VM_FOLDER:-/Lab/vm/OpenShift/$CLUSTER_NAME}"

echo "🧹 Deleting VMs in folder: $VM_FOLDER"
govc vm.destroy -folder="$VM_FOLDER" -dc="$(yq e '.vcenter_datacenter' "$CLUSTER_YAML")" "*" || true

echo "🗑️ Deleting install-configs directory for $CLUSTER_NAME"
INSTALL_DIR="$BASE_DIR/install-configs/$CLUSTER_NAME"
rm -rf "$INSTALL_DIR"

echo "✅ Cluster VMs and install artifacts removed for: $CLUSTER_NAME"
