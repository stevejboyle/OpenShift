#!/usr/bin/env bash
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPTS")"
export OPENSHIFT_INSTALL_PRESERVE_BOOTSTRAP=true

CLUSTER_YAML="$1"

if [[ -z "${CLUSTER_YAML:-}" || ! -f "$CLUSTER_YAML" ]]; then
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

log_step "5️⃣ Running openshift-install to create ignition configs..."
cp "$INSTALL_DIR"/install-config.yaml "$INSTALL_DIR"/install-config.yaml.bak
rm -rf "$INSTALL_DIR"/{*.ign,manifests,openshift}
openshift-install create manifests --dir="$INSTALL_DIR" --log-level=debug
openshift-install create ignition-configs --dir="$INSTALL_DIR" --log-level=debug

log_step "6️⃣ Generating network configurations to fix OVS conflicts..."
echo "🔧 Creating NetworkManager configs to override VM template OVS bridges..."
"$SCRIPTS/generate-network-manifests.sh" "$CLUSTER_YAML" "$INSTALL_DIR"

log_step "6.5️⃣ Merging network configs into ignition files..."
echo "🔧 Injecting network configurations into individual node ignition files..."
"$SCRIPTS/merge-network-ignition.sh" "$CLUSTER_YAML" "$INSTALL_DIR"

log_step "7️⃣ Deploying VMs with network-corrected ignition configs"
echo "🚀 Deploying VMs with ignition files that will override OVS configuration..."
"$SCRIPTS/deploy-vms.sh" "$CLUSTER_YAML" "$INSTALL_DIR"

log_step "8️⃣ Monitoring bootstrap progress (wait for completion)"
echo "⏳ Waiting for bootstrap to complete..."
echo "💡 This may take 15-30 minutes as nodes override OVS config and initialize OVN-Kubernetes..."

# Set kubeconfig for monitoring
export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"

# Wait for bootstrap completion with better error handling
BOOTSTRAP_TIMEOUT=3600  # 60 minutes timeout
BOOTSTRAP_START_TIME=$(date +%s)

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED_TIME=$((CURRENT_TIME - BOOTSTRAP_START_TIME))
  
  if [[ $ELAPSED_TIME -gt $BOOTSTRAP_TIMEOUT ]]; then
    echo "❌ Bootstrap timed out after ${BOOTSTRAP_TIMEOUT} seconds"
    echo "💡 Check cluster logs: openshift-install wait-for bootstrap-complete --dir=$INSTALL_DIR --log-level=debug"
    exit 1
  fi
  
  if openshift-install wait-for bootstrap-complete --dir="$INSTALL_DIR" --log-level=info; then
    echo "✅ Bootstrap completed successfully!"
    break
  else
    echo "⌛ Still waiting for bootstrap to complete... (elapsed: ${ELAPSED_TIME}s)"
    sleep 30
  fi
done

log_step "9️⃣ Removing bootstrap VM"
echo "🧹 Bootstrap removal is manual in this runbook."
# "$SCRIPTS/cleanup-bootstrap.sh" "$CLUSTER_YAML"

log_step "🔟 Waiting for cluster operators to stabilize..."
echo "⏳ Waiting for cluster installation to complete..."
if openshift-install wait-for install-complete --dir="$INSTALL_DIR" --log-level=info; then
  echo "✅ Cluster installation completed!"
else
  echo "⚠️  Installation monitoring failed, but cluster may still be completing..."
fi

log_step "1️⃣1️⃣ Applying taint fix and labels"
echo "🔧 Fixing cloud provider taints..."
"$SCRIPTS/fix-cloud-provider-taints.sh"
echo "🏷️  Applying node labels..."
"$SCRIPTS/label-nodes.sh" "$CLUSTER_YAML"

log_step "1️⃣2️⃣ Verifying cluster health"
for i in {1..40}; do
  AVAILABLE=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' || echo "")
  PROGRESSING=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Progressing")].status}' || echo "")
  DEGRADED=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Degraded")].status}' || echo "")
  echo "ClusterVersion: Available=$AVAILABLE Progressing=$PROGRESSING Degraded=$DEGRADED"
  if [[ "$AVAILABLE" == "True" && "$PROGRESSING" == "False" && "$DEGRADED" == "False" ]]; then
    echo "✅ Cluster healthy."
    break
  fi
  echo "⌛ Operators still settling… retry $i/40"
  sleep 15
done

echo -e "\n🎉 Cluster rebuild complete!"

log_step "🔐 Cluster access information"
KUBEADMIN_PASS_FILE="$INSTALL_DIR/auth/kubeadmin-password"
if [[ -f "$KUBEADMIN_PASS_FILE" ]]; then
  KUBEADMIN_PASS=$(cat "$KUBEADMIN_PASS_FILE")
  echo -e "✅ kubeadmin password: \033[1;33m$KUBEADMIN_PASS\033[0m"
  echo "🌐 Console URL: https://console-openshift-console.apps.$CLUSTER_NAME.$(yq e '.baseDomain' "$CLUSTER_YAML")"
  echo "🔐 Login via CLI:"
  echo "oc login -u kubeadmin -p $KUBEADMIN_PASS https://api.$CLUSTER_NAME.$(yq e '.baseDomain' "$CLUSTER_YAML"):6443"
  echo ""
  echo "📊 Quick health check commands:"
  echo "  oc get co"
  echo "  oc get nodes"  
  echo "  oc get pods -A | grep -v Running"
else
  echo "⚠️ kubeadmin password not found in $KUBEADMIN_PASS_FILE"
fi

echo ""
echo "💡 If you encounter OVS bridge issues:"
echo "   1. Check: ssh core@master-X 'sudo nmcli con show'"
echo "   2. Expected: No 'br-ex' or 'ovs-*' connections"
echo "   3. Expected: '${INTERFACE_NAME:-ens192}' ethernet connection with static IP"
echo "   4. Check OVN pods: oc get pods -n openshift-ovn-kubernetes"
