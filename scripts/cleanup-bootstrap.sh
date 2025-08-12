#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"

if [[ -z "${CLUSTER_YAML:-}" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

CLUSTER_NAME=$(yq e '.clusterName' "$CLUSTER_YAML")
BOOTSTRAP_VM_NAME="${CLUSTER_NAME}-bootstrap"

echo "🔍 Verifying that the OpenShift cluster is healthy before removing bootstrap..."

AVAILABLE=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
PROGRESSING=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Progressing")].status}' 2>/dev/null || echo "Unknown")
DEGRADED=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Degraded")].status}' 2>/dev/null || echo "Unknown")

echo "ClusterVersion: Available=$AVAILABLE Progressing=$PROGRESSING Degraded=$DEGRADED"
if [[ "$AVAILABLE" != "True" || "$PROGRESSING" != "False" || "$DEGRADED" != "False" ]]; then
  echo "❌ Cluster not fully healthy; aborting bootstrap removal."
  echo "ℹ️  Ensure 'oc' is authenticated and the cluster is stable."
  exit 1
fi

echo "✅ Cluster looks healthy. Proceeding to remove bootstrap node: $BOOTSTRAP_VM_NAME"

if ! govc vm.info "$BOOTSTRAP_VM_NAME" &>/dev/null; then
  echo "⚠️  Bootstrap VM not found: $BOOTSTRAP_VM_NAME"
  exit 0
fi

echo "⏻ Powering off bootstrap VM (if running)..."
govc vm.power -off -force "$BOOTSTRAP_VM_NAME" || echo "Already powered off."

echo "🗑️  Destroying bootstrap VM..."
govc vm.destroy "$BOOTSTRAP_VM_NAME"

echo "✅ Bootstrap node $BOOTSTRAP_VM_NAME has been removed."
