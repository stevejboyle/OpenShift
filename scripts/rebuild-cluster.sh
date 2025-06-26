#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ -z "${CLUSTER_YAML:-}" || ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

LOGFILE="/tmp/rebuild-cluster-$(basename "$CLUSTER_YAML" .yaml)-$(date +%s).log"
exec > >(tee "$LOGFILE") 2>&1

echo "🔁 Rebuilding cluster using config: $CLUSTER_YAML"
START_TS=$(date +%s)

SCRIPTS="$(dirname "$0")"
# Source load-vcenter-env.sh once at the beginning for all subsequent scripts
source "${SCRIPTS}/load-vcenter-env.sh"

log_step() {
  echo -e "\n⏱ $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Define INSTALL_DIR here so it's available for subsequent scripts
INSTALL_DIR="install-configs/$(yq eval '.clusterName' "$CLUSTER_YAML")"
CLUSTER_NAME="$(yq eval '.clusterName' "$CLUSTER_YAML")" # Get cluster name for HTTP server path

# Get Ignition Server details from YAML for starting the server
IGNITION_SERVER_IP=$(yq e '.ignition_server.host_ip' "$CLUSTER_YAML")
IGNITION_SERVER_PORT=$(yq e '.ignition_server.port' "$CLUSTER_YAML")

# 1. Validate vSphere credentials once at the very beginning
log_step "1️⃣ Validating vSphere credentials and resources..."
"${SCRIPTS}/validate-credentials.sh" "$CLUSTER_YAML"

log_step "2️⃣ Deleting previous cluster (if exists)..."
"${SCRIPTS}/delete-cluster.sh" "$CLUSTER_YAML"

log_step "3️⃣ Generating install-config.yaml..."
"${SCRIPTS}/generate-install-config.sh" "$CLUSTER_YAML"

log_step "4️⃣ Creating OpenShift manifests and initial ignition configs..."
"${SCRIPTS}/configure-cluster.sh" "$CLUSTER_YAML"

log_step "5️⃣ Injecting vSphere credentials into manifests..."
"${SCRIPTS}/generate-vsphere-creds-manifest.sh" "$CLUSTER_YAML"

log_step "6️⃣ Generating static IP manifests (if configured)..."
"${SCRIPTS}/generate-static-ip-manifests.sh" "$CLUSTER_YAML"

log_step "7️⃣ Creating config-drive ISO images (these are NOT used for Ignition, only if needed for debug/backup)..."
# The create-config-cdroms.sh script still exists, but the VMs won't use these for Ignition.
# It might be entirely removed from your workflow if not explicitly desired for other purposes.
"${SCRIPTS}/create-config-cdroms.sh" "$CLUSTER_YAML"


log_step "8️⃣ Starting HTTP server for Ignition delivery (serving from ${INSTALL_DIR})..."
# Start a Python simple HTTP server in the INSTALL_DIR in the background.
# This serves all .ign files.
(cd "${INSTALL_DIR}" && python3 -m http.server "$IGNITION_SERVER_PORT" &>/dev/null &)
HTTP_SERVER_PID=$!
echo "✅ HTTP server started on http://${IGNITION_SERVER_IP}:${IGNITION_SERVER_PORT} with PID: $HTTP_SERVER_PID"
echo "   Serving Ignition files from: ${INSTALL_DIR}"
# Ensure the HTTP server is killed when the script exits
trap "kill $HTTP_SERVER_PID || true; echo 'HTTP server (PID $HTTP_SERVER_PID) stopped.'" EXIT

log_step "9️⃣ Deploying VMs..."
"${SCRIPTS}/deploy-vms.sh" "$CLUSTER_YAML" "$INSTALL_DIR" "$IGNITION_SERVER_IP" "$IGNITION_SERVER_PORT"

log_step "🔟 Monitoring bootstrap progress (this may take 15-30 minutes)..."
if ! "${SCRIPTS}/monitor-bootstrap.sh" "$CLUSTER_YAML"; then
  echo "❌ Bootstrap failed or timed out. Check logs: $LOGFILE"
  exit 1
fi
echo "✅ Bootstrap complete!"

log_step "1️⃣1️⃣ Fixing cloud provider taints..."
if ! "${SCRIPTS}/fix-cloud-provider-taints.sh" "$INSTALL_DIR"; then
  echo "⚠️ Failed to remove cloud provider taints. This may indicate an issue with cloud-controller-manager."
fi

# The HTTP server will be killed automatically by the trap on EXIT.
END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
echo -e "\n🎉 Rebuild complete in $((DURATION / 60))m $((DURATION % 60))s"
echo "📄 Full log saved at: $LOGFILE"
