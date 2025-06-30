#!/usr/bin/env bash
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPTS")"

CLUSTER_YAML="$1"

if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

CLUSTER_NAME=$(yq e '.clusterName' "$CLUSTER_YAML")
INSTALL_DIR="$BASE_DIR/install-configs/$CLUSTER_NAME"

# Load vCenter environment variables
source "${SCRIPTS}/load-vcenter-env.sh"

log_step() {
  echo -e "\n⏱ $(date +'%F %T') - $1"
}

log_step "1️⃣ Validating input YAML file..."
echo "✅ Cluster name: $CLUSTER_NAME"
echo "✅ Install directory: $INSTALL_DIR"

log_step "2️⃣ Cleaning up previous install directory..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
echo "✅ Directory reset: $INSTALL_DIR"

log_step "3️⃣ Generating install-config.yaml"
"$SCRIPTS/generate-install-config.sh" "$CLUSTER_YAML"

log_step "3️⃣c Running openshift-install to create ignition configs..."
timestamp=$(date +%Y%m%d-%H%M%S)
cp "$INSTALL_DIR/install-config.yaml" "$INSTALL_DIR/install-config.yaml.$timestamp.bak"
openshift-install create manifests --dir="$INSTALL_DIR"
openshift-install create ignition-configs --dir="$INSTALL_DIR"
echo "✅ Ignition configs generated at $INSTALL_DIR"

log_step "4️⃣ Injecting vSphere credentials into manifests"
"$SCRIPTS/generate-vsphere-creds-manifest.sh" "$CLUSTER_YAML"

log_step "5️⃣ Deploying VMs"
"$SCRIPTS/deploy-vms.sh" "$CLUSTER_YAML"

log_step "6️⃣ Monitoring bootstrap progress (wait for completion)"
echo "⏳ Waiting for bootstrap to complete..."
while true; do
  BOOTSTRAP_STATUS=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
  if [[ "$BOOTSTRAP_STATUS" == "True" ]]; then
    echo "✅ Bootstrap completed."
    break
  fi
  echo "⌛ Still waiting for bootstrap to complete..."
  sleep 30
done

log_step "7️⃣ Removing bootstrap VM"
"$SCRIPTS/cleanup-bootstrap.sh" "$CLUSTER_YAML"

log_step "8️⃣ Applying taint fix and node labels"
"$SCRIPTS/fix-cloud-provider-taints.sh"
"$SCRIPTS/label-nodes.sh" "$CLUSTER_YAML"

echo -e "\n🎉 Cluster rebuild complete."
