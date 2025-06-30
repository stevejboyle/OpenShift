#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"

if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

CLUSTER_NAME=$(yq e '.clusterName' "$CLUSTER_YAML")
BOOTSTRAP_VM_NAME="${CLUSTER_NAME}-bootstrap"

echo "🔍 Verifying that the OpenShift cluster has completed bootstrap..."

BOOTSTRAP_COMPLETE=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")

if [[ "$BOOTSTRAP_COMPLETE" != "True" ]]; then
  echo "❌ Bootstrap process is not complete or unreachable!"
  echo "ℹ️  Ensure the cluster is available and 'oc' is authenticated."
  exit 1
fi

echo "✅ Bootstrap process appears complete."
echo "🧹 Proceeding to clean up bootstrap node: $BOOTSTRAP_VM_NAME"

# Check if the VM exists
if ! govc vm.info "$BOOTSTRAP_VM_NAME" &>/dev/null; then
  echo "⚠️  Bootstrap VM not found: $BOOTSTRAP_VM_NAME"
  exit 0
fi

# Power off the VM if it is running
echo "⏻ Powering off bootstrap VM (if running)..."
govc vm.power -off -force "$BOOTSTRAP_VM_NAME" || echo "Already powered off."

# Destroy the VM
echo "🗑️ Destroying bootstrap VM..."
govc vm.destroy "$BOOTSTRAP_VM_NAME"

echo "✅ Bootstrap node $BOOTSTRAP_VM_NAME has been removed."
