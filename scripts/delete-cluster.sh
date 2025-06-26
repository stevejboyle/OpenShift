#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster config not found: $CLUSTER_YAML"
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPTS_DIR}/load-vcenter-env.sh"

echo "✅ Successfully loaded and validated vSphere credentials"

# Read cluster config
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
DATASTORE="${GOVC_DATASTORE}"
VMF="${GOVC_FOLDER}/${CLUSTER_NAME}" # Assuming GOVC_FOLDER is defined, else this might be empty
ISO_FOLDER="[${DATASTORE}] iso/${CLUSTER_NAME}"
MANIFEST_DIR="./install-configs/${CLUSTER_NAME}"

# Define VMs (adjust if you change worker count or names)
VMS=("${CLUSTER_NAME}-bootstrap" "${CLUSTER_NAME}-master-0" "${CLUSTER_NAME}-master-1" "${CLUSTER_NAME}-master-2" "${CLUSTER_NAME}-worker-0" "${CLUSTER_NAME}-worker-1")

echo "🛑 Shutting down and deleting VMs (if exist)..."
for vm in "${VMS[@]}"; do
  if govc vm.info "$vm" &>/dev/null; then
    echo "⚙️ Powering off $vm (if powered on)..."
    govc vm.power -off "$vm" || true

    echo "🧹 Destroying $vm..."
    govc vm.destroy "$vm" || echo "⚠️ Failed to delete $vm (may not exist)"
  else
    echo "ℹ️ VM $vm does not exist, skipping"
  fi
done

# Delete VM folder (if exists)
echo "🧼 Removing folder $VMF (if exists)..."
govc object.destroy "$VMF" || echo "⚠️ Folder not found or already removed: $VMF"

# Delete ISOs from datastore (if exists)
echo "🗑 Deleting ISOs from $ISO_FOLDER..."
if govc datastore.ls "$ISO_FOLDER" &>/dev/null; then
  govc datastore.rm -f "$ISO_FOLDER" || echo "⚠️ Could not remove ISO directory"
else
  echo "ℹ️ ISO directory not found"
fi

# Delete manifests and install configs locally
echo "🗑 Deleting manifests and install-configs for $CLUSTER_NAME..."
rm -rf "${MANIFEST_DIR:?}" || echo "⚠️ Could not remove install-configs/${CLUSTER_NAME}"

echo "✅ Cluster $CLUSTER_NAME cleaned up successfully."