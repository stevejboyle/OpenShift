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
CLUSTER_NAME="$(yq eval '.clusterName' "$CLUSTER_YAML")" # Get cluster name

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

log_step "7️⃣ Deploying VMs..." # Re-numbered step
"${SCRIPTS}/deploy-vms.sh" "$CLUSTER_YAML" "$INSTALL_DIR"

log_step "8️⃣ Monitoring bootstrap progress (this may take 15-30 minutes)..." # Re-numbered step
if ! "${SCRIPTS}/monitor-bootstrap.sh" "$CLUSTER_YAML"; then
  echo "❌ Bootstrap failed or timed out. Check logs: $LOGFILE"
  exit 1
fi
echo "✅ Bootstrap complete!"

log_step "9️⃣ Fixing cloud provider taints..." # Re-numbered step
if ! "${SCRIPTS}/fix-cloud-provider-taints.sh" "$INSTALL_DIR"; then
  echo "⚠️ Failed to remove cloud provider taints. This may indicate an issue with cloud-controller-manager."
fi

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
echo -e "\n🎉 Rebuild complete in $((DURATION / 60))m $((DURATION % 60))s"
echo "📄 Full log saved at: $LOGFILE"
