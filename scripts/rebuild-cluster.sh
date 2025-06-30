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
source "$SCRIPTS/load-vcenter-env.sh"

log_step() {
  echo -e "\n⏱ $(date +'%F %T') - $1"
}

log_step "1️⃣ Validating input YAML file..."
echo "✅ Cluster name: $CLUSTER_NAME"
echo "✅ Install directory: $INSTALL_DIR"

log_step "2️⃣ Deleting previous cluster (if exists)..."
"$SCRIPTS/delete-cluster.sh" "$CLUSTER_YAML"

log_step "3️⃣ Cleaning up previous install directory..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
echo "✅ Directory reset: $INSTALL_DIR"

log_step "4️⃣ Generating install-config.yaml"
"$SCRIPTS/generate-install-config.sh" "$CLUSTER_YAML"
cp "$INSTALL_DIR/install-config.yaml" "$INSTALL_DIR/install-config.yaml.bak"
echo "✅ install-config.yaml backed up"

log_step "5️⃣ Running openshift-install to create ignition configs..."
openshift-install create manifests --dir="$INSTALL_DIR"
openshift-install create ignition-configs --dir="$INSTALL_DIR"
echo "✅ Ignition configs generated at $INSTALL_DIR"

log_step "7️⃣ Deploying VMs"
"$SCRIPTS/deploy-vms.sh" "$CLUSTER_YAML"

log_step "8️⃣ Monitoring bootstrap progress (wait for completion)"
echo "⏳ Waiting for bootstrap to complete..."
while true; do
  BOOTSTRAP_STATUS=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
  if [[ "$BOOTSTRAP_STATUS" == "True" ]]; then
    echo "✅ Bootstrap completed."
    break
  fi
  echo "⌛ Still waiting for bootstrap to complete..."
  sleep 30
  # optional: add timeout logic here
done

log_step "9️⃣ Removing bootstrap VM"
"$SCRIPTS/cleanup-bootstrap.sh" "$CLUSTER_YAML"

log_step "🔟 Applying taint fix and labels"
"$SCRIPTS/fix-cloud-provider-taints.sh"
"$SCRIPTS/label-nodes.sh" "$CLUSTER_YAML"

echo "🎉 Cluster rebuild complete."

# Final step: Show kubeadmin login information
log_step "🔐 Cluster access information"
KUBEADMIN_PASS_FILE="$INSTALL_DIR/auth/kubeadmin-password"
if [[ -f "$KUBEADMIN_PASS_FILE" ]]; then
  KUBEADMIN_PASS=$(cat "$KUBEADMIN_PASS_FILE")
  echo -e "✅ kubeadmin password: \033[1;33m$KUBEADMIN_PASS\033[0m"
  echo "🌐 Console URL: https://console-openshift-console.apps.$CLUSTER_NAME.$(yq e '.baseDomain' "$CLUSTER_YAML")"
  echo "🔐 Login via CLI:"
  echo "oc login -u kubeadmin -p $KUBEADMIN_PASS https://api.$CLUSTER_NAME.$(yq e '.baseDomain' "$CLUSTER_YAML"):6443"
else
  echo "⚠️ kubeadmin password not found in $KUBEADMIN_PASS_FILE"
fi
