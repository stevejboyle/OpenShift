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

# Ensure we kill the HTTP server on exit (best-effort)
HTTP_SERVER_PID=""
cleanup_http() {
  if [[ -n "${HTTP_SERVER_PID:-}" ]]; then
    echo "🧹 Stopping Ignition server (PID ${HTTP_SERVER_PID})..."
    kill "${HTTP_SERVER_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup_http EXIT

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
"$SCRIPTS/generate-network-manifests.sh" "$CLUSTER_YAML" "$INSTALL_DIR"

log_step "6.5️⃣ Merging network configs into ignition files..."
"$SCRIPTS/merge-network-ignition.sh" "$CLUSTER_YAML" "$INSTALL_DIR"

# --- New: start Ignition HTTP server on port 8088 ---
log_step "6.8️⃣ Starting Ignition HTTP server (port 8088)"
IGN_DIR="${INSTALL_DIR}"
IGN_PORT=8088
# Start server in background
"$SCRIPTS/start-ignition-server.sh" "$IGN_DIR" "$IGN_PORT" &
HTTP_SERVER_PID=$!
sleep 2
# Lightweight health check
if curl -sSf -o /dev/null "http://127.0.0.1:${IGN_PORT}/"; then
  echo "✅ Ignition server is responding locally on port ${IGN_PORT}."
else
  echo "⚠️  Ignition server did not respond locally; continuing, but VMs may fail to fetch."
fi

log_step "7️⃣ Deploying VMs with ignition via URL"
"$SCRIPTS/deploy-vms.sh" "$CLUSTER_YAML" "$INSTALL_DIR"

log_step "8️⃣ Monitoring bootstrap progress (wait for completion)"
export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"
BOOTSTRAP_TIMEOUT=3600
BOOTSTRAP_START_TIME=$(date +%s)

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED_TIME=$((CURRENT_TIME - BOOTSTRAP_START_TIME))
  if [[ $ELAPSED_TIME -gt $BOOTSTRAP_TIMEOUT ]]; then
    echo "❌ Bootstrap timed out after ${BOOTSTRAP_TIMEOUT} seconds"
    echo "💡 Check logs: openshift-install wait-for bootstrap-complete --dir=$INSTALL_DIR --log-level=debug"
    exit 1
  fi
  if openshift-install wait-for bootstrap-complete --dir="$INSTALL_DIR" --log-level=info; then
    echo "✅ Bootstrap completed successfully!"
    break
  else
    echo "⌛ Still waiting for bootstrap... (elapsed: ${ELAPSED_TIME}s)"
    sleep 30
  fi
done

log_step "9️⃣ Removing bootstrap VM"
echo "🧹 Bootstrap removal is manual in this runbook."
# "$SCRIPTS/cleanup-bootstrap.sh" "$CLUSTER_YAML"

log_step "🔟 Waiting for cluster operators to stabilize..."
if openshift-install wait-for install-complete --dir="$INSTALL_DIR" --log-level=info; then
  echo "✅ Cluster installation completed!"
else
  echo "⚠️  Installation monitoring failed, but cluster may still be completing..."
fi

log_step "1️⃣1️⃣ Applying taint fix and labels"
"$SCRIPTS/fix-cloud-provider-taints.sh"
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
else
  echo "⚠️ kubeadmin password not found at $KUBEADMIN_PASS_FILE"
fi

echo ""
echo "💡 If you encounter OVS bridge issues:"
echo "   ssh core@master-X 'sudo nmcli con show'  # Expect no br-ex / ovs-*"
