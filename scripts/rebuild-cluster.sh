#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

CLUSTER_YAML="$(realpath "$1")"
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
"$SCRIPT_DIR/delete-cluster.sh" --force "$CLUSTER_YAML"

echo "⚙ Generating install-config.yaml..."
"$SCRIPT_DIR/generate-install-config.sh" "$CLUSTER_YAML"

echo "📦 Creating manifests..."
cd "$INSTALL_DIR"
openshift-install create manifests
cd "$SCRIPT_DIR"

echo "🌐 Injecting static IP manifests..."
"$SCRIPT_DIR/generate-static-ip-manifests.sh" "$CLUSTER_YAML"

echo "🔑 Injecting core user password manifests..."
"$SCRIPT_DIR/generate-core-password-manifest.sh" "$CLUSTER_YAML"

echo "🔐 Injecting vSphere creds secret..."
"$SCRIPT_DIR/generate-vsphere-creds-manifest.sh" "$CLUSTER_NAME"

echo "🔑 Injecting console-password manifest..."
"$SCRIPT_DIR/generate-console-password-manifests.sh" "$CLUSTER_YAML"

echo "📋 Backing up manifests for debugging..."
BACKUP_DIR="${INSTALL_DIR}/manifests-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r "${INSTALL_DIR}/manifests/"* "$BACKUP_DIR/"
echo "✅ Manifests backed up to: $BACKUP_DIR"

echo "🔍 Custom manifests that will be applied:"
ls -la "${INSTALL_DIR}/manifests/99-"* "${INSTALL_DIR}/manifests/vsphere-"* 2>/dev/null || echo "   No custom manifests found"

echo "🔥 Generating ignition-configs..."
cd "$INSTALL_DIR"
openshift-install create ignition-configs
cd "$SCRIPT_DIR"

echo "🌐 Injecting static IPs directly into ignition files..."
"$SCRIPT_DIR/inject-static-ips-into-ignition.sh" "$CLUSTER_YAML"

echo "🚀 Deploying VMs..."
"$SCRIPT_DIR/deploy-vms.sh" "$CLUSTER_YAML"

echo "🎉 Full rebuild complete with static IPs!"
echo "📋 Manifest backup available at: $BACKUP_DIR"

echo ""
echo "🔍 Verifying static IP injection..."
if cat "${INSTALL_DIR}/bootstrap.ign" | jq '.storage.files[] | select(.path | contains("system-connections"))' | grep -q "path"; then
  echo "✅ Static IP configuration found in bootstrap ignition file"
else
  echo "❌ Static IP configuration NOT found in bootstrap ignition file"
  echo "🔍 Check manifest backup at: $BACKUP_DIR"
fi
