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
  echo
  echo "⏱ $(date '+%F %T') - $1..."
}

log_step "1️⃣ Deleting previous cluster (if exists)"
"${SCRIPTS}/delete-cluster.sh" "$CLUSTER_YAML"

log_step "2️⃣ Generating vsphere credentials manifest"
"${SCRIPTS}/generate-vsphere-creds-manifest.sh" "$CLUSTER_YAML"

log_step "3️⃣ Generating install-config.yaml"
"${SCRIPTS}/generate-install-config.sh" "$CLUSTER_YAML"

log_step "4️⃣ Generating console user/password manifest"
"${SCRIPTS}/generate-console-password-manifests.sh" "$CLUSTER_YAML"

log_step "5️⃣ Generating core user/password manifest"
"${SCRIPTS}/generate-core-user-password.sh" "$CLUSTER_YAML"

log_step "6️⃣ Deploying VMs"
"${SCRIPTS}/deploy-vms.sh" "$CLUSTER_YAML"

log_step "7️⃣ Monitoring bootstrap process"
"${SCRIPTS}/monitor-bootstrap.sh" "$CLUSTER_YAML"

END_TS=$(date +%s)
echo "✅ Cluster rebuild complete in $((END_TS - START_TS)) seconds"
