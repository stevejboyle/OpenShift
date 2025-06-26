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

# 1. Validate vSphere credentials once at the very beginning
log_step "1️⃣ Validating vSphere credentials and resources..."
"${SCRIPTS}/validate-credentials.sh" "$CLUSTER_YAML"

log_step "2️⃣ Deleting previous cluster (if exists)..."
"${SCRIPTS}/delete-cluster.sh" "$CLUSTER_YAML"

log_step "3️⃣ Generating install-config.yaml..."
"${SCRIPTS}/generate-install-config.sh" "$CLUSTER_YAML"

# NOTE: Step 4 in your original script called 'deploy-cluster.sh' for "Creating manifests..."
# Based on the content provided, the script handling manifests and ignition configs is likely
# what was previously identified as 'configure-cluster.sh' (Source: 14-18 in scripts.txt).
# Please ensure the filename matches what's being called here.
log_step "4️⃣ Creating OpenShift manifests and initial ignition configs..."
"${SCRIPTS}/configure-cluster.sh" "$CLUSTER_YAML" # Assuming 'configure-cluster.sh' is the actual filename

log_step "5️⃣ Injecting vSphere credentials into manifests..."
"${SCRIPTS}/generate-vsphere-creds-manifest.sh" "$CLUSTER_YAML"

log_step "6️⃣ Generating static IP manifests (if configured)..."
"${SCRIPTS}/generate-static-ip-manifests.sh" "$CLUSTER_YAML"

# NOTE: Step 7 in your original script was "Creating individual ignition files...".
# The 'configure-cluster.sh' already calls 'openshift-install create ignition-configs'.
# If you have another script for this, verify its purpose.
# Assuming 'configure-cluster.sh' (my step 4) handles this.
# If 'create-individual-node-ignitions.sh' exists and has a unique purpose, you can re-add it here.

log_step "7️⃣ Creating config-drive ISO images (if needed for older boot methods)..."
# As discussed, if relying purely on guestinfo.ignition.config.data, these ISOs might be redundant for boot.
# They might still be useful for manual inspection or other purposes.
"${SCRIPTS}/create-config-cdroms.sh" "$CLUSTER_YAML"

log_step "8️⃣ Deploying VMs..."
"${SCRIPTS}/deploy-vms.sh" "$CLUSTER_YAML"

log_step "9️⃣ Monitoring bootstrap progress (this may take 15-30 minutes)..."
# Added more robust wait and feedback
if ! "${SCRIPTS}/monitor-bootstrap.sh" "$CLUSTER_YAML"; then
  echo "❌ Bootstrap failed or timed out. Check logs: $LOGFILE"
  exit 1
fi
echo "✅ Bootstrap complete!"


log_step "🔟 Fixing cloud provider taints..."
if ! "${SCRIPTS}/fix-cloud-provider-taints.sh" "$CLUSTER_YAML"; then
  echo "⚠️ Failed to remove cloud provider taints. This may indicate an issue with cloud-controller-manager."
  # Not making this a hard exit, as cluster might still function, but requires attention.
fi

# The original script had a second validate-credentials.sh call here.
# Removed as it's redundant if validated at the start and cluster is up.

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
echo -e "\n🎉 Rebuild complete in $((DURATION / 60))m $((DURATION % 60))s"
echo "📄 Full log saved at: $LOGFILE"