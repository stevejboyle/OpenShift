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
source "${SCRIPTS}/load-vcenter-env.sh"

log_step() {
  echo -e "\n⏱ $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_step "1️⃣ Validating vSphere credentials..."
"${SCRIPTS}/validate-credentials.sh" "$CLUSTER_YAML"

log_step "2️⃣ Deleting previous cluster (if exists)..."
"${SCRIPTS}/delete-cluster.sh" "$CLUSTER_YAML"

log_step "3️⃣ Generating install-config.yaml..."
"${SCRIPTS}/generate-install-config.sh" "$CLUSTER_YAML"

log_step "4️⃣ Creating manifests..."
"${SCRIPTS}/deploy-cluster.sh" "$CLUSTER_YAML"

log_step "5️⃣ Injecting vSphere credentials into manifests..."
"${SCRIPTS}/generate-vsphere-creds-manifest.sh" "$CLUSTER_YAML"

log_step "6️⃣ Generating static IP manifests..."
"${SCRIPTS}/generate-static-ip-manifests.sh" "$CLUSTER_YAML"

log_step "7️⃣ Creating individual ignition files..."
"${SCRIPTS}/create-individual-node-ignitions.sh" "$CLUSTER_YAML"

log_step "8️⃣ Creating config-drive ISO images..."
"${SCRIPTS}/create-config-cdroms.sh" "$CLUSTER_YAML"

log_step "9️⃣ Deploying VMs..."
"${SCRIPTS}/deploy-vms.sh" "$CLUSTER_YAML"

log_step "🔟 Monitoring bootstrap progress..."
"${SCRIPTS}/monitor-bootstrap.sh" "$CLUSTER_YAML" || echo "⚠️ Bootstrap may have failed"

log_step "🔁 Fixing cloud provider taints..."
"${SCRIPTS}/fix-cloud-provider-taints.sh" "$CLUSTER_YAML" || echo "⚠️ Taint fix may have failed"

log_step "✅ Validating deployed credentials..."
"${SCRIPTS}/validate-credentials.sh" "$CLUSTER_YAML"

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
echo -e "\n🎉 Rebuild complete in $((DURATION / 60))m $((DURATION % 60))s"
echo "📄 Full log saved at: $LOGFILE"
