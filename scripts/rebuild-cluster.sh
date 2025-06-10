#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

CLUSTER_YAML="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

if [ ! -f "$CLUSTER_YAML" ]; then
  echo "❌ Cluster file not found: $CLUSTER_YAML"
  exit 1
fi

# Get cluster name for directory structure
CLUSTER_NAME=$(yq -r '.clusterName' "$CLUSTER_YAML")
INSTALL_DIR="$BASE_DIR/install-configs/$CLUSTER_NAME"

# Load govc.env for GOVC_URL, USERNAME, etc
if [ ! -f "$BASE_DIR/govc.env" ]; then
  echo "❌ govc.env not found in $BASE_DIR"
  exit 1
fi
source "$BASE_DIR/govc.env"

# -------------------------
# << Prompt exactly once here >>
echo -n "🔐 Enter vSphere password for $GOVC_USERNAME: "
read -s GOVC_PASSWORD
echo
export GOVC_PASSWORD

# Export for openshift-install
export VSPHERE_USERNAME="$GOVC_USERNAME"
export VSPHERE_PASSWORD="$GOVC_PASSWORD"
export OPENSHIFT_INSTALL_EXPERIMENTAL_OVERRIDES='{ "disableTemplatedInstallConfig": true }'
# -------------------------

echo "🧹 Cleaning up any existing cluster..."
"$SCRIPT_DIR/delete-cluster.sh" "$CLUSTER_YAML"

echo "⚙ Generating install-config.yaml..."
"$SCRIPT_DIR/generate-install-config.sh" "$CLUSTER_YAML"

echo "📦 Creating manifests..."
cd "$INSTALL_DIR"
openshift-install create manifests
cd "$SCRIPT_DIR"

echo "🔐 Injecting vSphere creds secret..."
"$SCRIPT_DIR/generate-vsphere-creds-manifest.sh" "$CLUSTER_NAME"

echo "🔑 Injecting console-password manifest..."
"$SCRIPT_DIR/generate-console-password-manifests.sh" "$CLUSTER_YAML"

echo "🔥 Generating ignition-configs..."
cd "$INSTALL_DIR"
openshift-install create ignition-configs
cd "$SCRIPT_DIR"

echo "🚀 Deploying VMs..."
"$SCRIPT_DIR/deploy-vms.sh" "$CLUSTER_YAML"

echo "🎉 Full rebuild complete!"
