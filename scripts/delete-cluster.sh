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
# Construct the full path for the cluster's VM folder based on GOVC_FOLDER
# Example: /Lab/vm/OpenShift/ocp416
VM_CLUSTER_FOLDER_NAME="${CLUSTER_NAME}"
VMF="${GOVC_FOLDER}/${VM_CLUSTER_FOLDER_NAME}"

ISO_FOLDER="[${DATASTORE}] iso/${CLUSTER_NAME}"
MANIFEST_DIR="./install-configs/${CLUSTER_NAME}"

# --- NEW: Dynamically build VMS array from cluster YAML ---
MASTER_REPLICAS=$(yq eval '.node_counts.master' "$CLUSTER_YAML")
WORKER_REPLICAS=$(yq eval '.node_counts.worker' "$CLUSTER_YAML")

VMS=("${CLUSTER_NAME}-bootstrap") # Bootstrap node is always present

for i in $(seq 0 $((MASTER_REPLICAS - 1))); do
  VMS+=("${CLUSTER_NAME}-master-${i}")
done

for i in $(seq 0 $((WORKER_REPLICAS - 1))); do
  VMS+=("${CLUSTER_NAME}-worker-${i}")
done

echo "🛑 Shutting down and deleting VMs: ${VMS[@]} (if exist)..."
# --- END NEW NODE BUILD ---

for vm in "${VMS[@]}"; do
  if govc vm.info "$vm" &>/dev/null; then
    echo "⚙️ Powering off $vm (if powered on)..."
    govc vm.power -off "$vm" || true

    echo "🧹 Destroying $vm..."
    # Ensure to use the full path for destruction to avoid ambiguity
    govc vm.destroy -vm.ipath="${VMF}/${vm}" || echo "⚠️ Failed to delete $vm (may not exist)"
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