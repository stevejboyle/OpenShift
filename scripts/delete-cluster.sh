#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="${1:-}"
if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "❌ Cluster file not found: $CLUSTER_YAML"
  exit 1
fi

SCRIPTS_DIR="$(dirname "$0")"
source "${SCRIPTS_DIR}/load-vcenter-env.sh"

CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
VM_FOLDER="${GOVC_FOLDER}/${CLUSTER_NAME}"
DATASTORE="${GOVC_DATASTORE:?❌ GOVC_DATASTORE not set}"
ISO_DIR="iso/${CLUSTER_NAME}"

VMS=(
  "${CLUSTER_NAME}-bootstrap"
  "${CLUSTER_NAME}-master-0"
  "${CLUSTER_NAME}-master-1"
  "${CLUSTER_NAME}-master-2"
  "${CLUSTER_NAME}-worker-0"
  "${CLUSTER_NAME}-worker-1"
)

echo "🧨 Deleting VMs for cluster: $CLUSTER_NAME"
for vm in "${VMS[@]}"; do
  if govc vm.info "$vm" &>/dev/null; then
    echo "🔌 Powering off $vm (if running)..."
    govc vm.power -off "$vm" -force || true

    echo "🗑️  Destroying VM: $vm"
    govc vm.destroy "$vm" || true
  else
    echo "⚠️  VM not found: $vm (already deleted)"
  fi
done

echo "🧹 Removing VM folder: $VM_FOLDER (if empty)..."
govc object.destroy "$VM_FOLDER" || echo "⚠️  Folder not removed (may not exist or not empty)"

echo "💿 Removing ISO files from datastore: $ISO_DIR"
for vm in "${VMS[@]}"; do
  ISO_PATH="[${DATASTORE}] ${ISO_DIR}/${vm}.iso"
  govc datastore.rm "$ISO_PATH" || echo "⚠️  Could not delete $ISO_PATH (may not exist)"
done

# Remove install-configs and manifests
INSTALL_DIR="$(dirname "$CLUSTER_YAML")"
CLUSTER_INSTALL_DIR="${INSTALL_DIR}/install-configs/${CLUSTER_NAME}"
echo "🧽 Cleaning up install-config directory: $CLUSTER_INSTALL_DIR"
rm -rf "$CLUSTER_INSTALL_DIR"

echo "🧽 Cleaning up manifests: manifests/ and openshift/"
rm -rf manifests/ openshift/ cluster-api/

echo "✅ Cluster cleanup complete for: $CLUSTER_NAME"
