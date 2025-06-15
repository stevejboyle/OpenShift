#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "❌ Cluster file not found: $1"
  exit 1
fi

SCRIPTS="$(dirname "$0")"
BASE_DIR="$(cd "$SCRIPTS/.." && pwd)"

# Load vSphere env
source "$SCRIPTS/load-vcenter-env.sh"

# Cleanup old state
"$SCRIPTS/delete-cluster.sh" "$CLUSTER_YAML"

# Validate vSphere credentials
"$SCRIPTS/validate-credentials.sh" "$CLUSTER_YAML"

# Generate base install-config.yaml
"$SCRIPTS/generate-install-config.sh" "$CLUSTER_YAML"

# Generate manifests
cd "$BASE_DIR/install-configs/$(yq '.clusterName' "$CLUSTER_YAML")"
echo "🛠 Generating manifests..."
openshift-install create manifests

# Inject vSphere credentials manifest (new step)
echo "🔐 Injecting vSphere credentials secret..."
"$SCRIPTS/generate-vsphere-creds-manifest.sh" "$CLUSTER_YAML"

# Optional: inject console password and cloud credentials
"$SCRIPTS/generate-console-password-manifests.sh" "$CLUSTER_YAML"
"$SCRIPTS/generate-vsphere-creds-manifest.sh" "$CLUSTER_YAML"

# Generate static IP NetworkManager configs
"$SCRIPTS/generate-static-ip-manifests.sh" "$CLUSTER_YAML"

# Create Ignition configs
echo "📦 Creating Ignition configs..."
openshift-install create ignition-configs

# Create per-node ignition files with static IPs
"$SCRIPTS/create-individual-node-ignitions.sh" "$CLUSTER_YAML"

# Deploy VMs with ignition configs
"$SCRIPTS/deploy-vms.sh" "$CLUSTER_YAML"

# Wait for bootstrap to complete
openshift-install wait-for bootstrap-complete --log-level debug

# Fix cloud provider taints
"$SCRIPTS/fix-cloud-provider-taints.sh" "$BASE_DIR/install-configs/$(yq '.clusterName' "$CLUSTER_YAML")"

# Wait for install to complete
openshift-install wait-for install-complete --log-level debug

# Validate deployed credentials
"$SCRIPTS/validate-credentials.sh" "$CLUSTER_YAML"

echo "✅ Cluster $(yq '.clusterName' "$CLUSTER_YAML") deployed successfully."
