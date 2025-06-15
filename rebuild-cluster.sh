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

echo "🌐 Generating static IP manifests..."
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

echo "🌐 Creating individual node ignition files with static IPs..."
"$SCRIPT_DIR/inject-static-ips-into-ignition.sh" "$CLUSTER_YAML"

echo "🌐 Creating individual node ignition files with static IPs..."
"$SCRIPT_DIR/create-individual-node-ignitions.sh" "$CLUSTER_YAML"

echo "🚀 Deploying VMs..."
"$SCRIPT_DIR/deploy-vms.sh" "$CLUSTER_YAML"

echo "🎉 VM deployment complete!"

# NEW: Wait for cluster bootstrap and handle cloud provider taints
echo ""
echo "⏳ Waiting for cluster bootstrap to complete..."
cd "$INSTALL_DIR"
echo "   Starting bootstrap wait (this may take 20-30 minutes)..."

# Run openshift-install wait-for bootstrap-complete with our own timeout handling
echo "   This may take up to 40 minutes..."
BOOTSTRAP_PID=""
openshift-install wait-for bootstrap-complete --log-level=info &
BOOTSTRAP_PID=$!

# Wait for bootstrap with timeout (40 minutes = 2400 seconds)
TIMEOUT_SECONDS=2400
ELAPSED=0
BOOTSTRAP_EXIT_CODE=""

while [ $ELAPSED -lt $TIMEOUT_SECONDS ]; do
  if ! kill -0 $BOOTSTRAP_PID 2>/dev/null; then
    # Process has finished
    wait $BOOTSTRAP_PID
    BOOTSTRAP_EXIT_CODE=$?
    break
  fi
  sleep 30
  ELAPSED=$((ELAPSED + 30))
  echo "   Bootstrap wait progress: $ELAPSED/$TIMEOUT_SECONDS seconds..."
done

# Handle the result
if [ -n "$BOOTSTRAP_EXIT_CODE" ]; then
  if [ $BOOTSTRAP_EXIT_CODE -eq 0 ]; then
    echo "✅ Bootstrap completed successfully"
  else
    echo "❌ Bootstrap failed with exit code $BOOTSTRAP_EXIT_CODE"
    echo "   Still attempting to check and fix cloud provider taints..."
  fi
else
  # Timed out - kill the process
  echo "⚠️  Bootstrap wait timed out after 40 minutes, but this may be due to cloud provider initialization issues"
  echo "   Proceeding to check and fix cloud provider taints..."
  kill $BOOTSTRAP_PID 2>/dev/null || true
  wait $BOOTSTRAP_PID 2>/dev/null || true
fi

cd "$SCRIPT_DIR"

# NEW: Check and fix cloud provider taints
echo ""
echo "🔧 Checking and fixing cloud provider initialization issues..."
if "$SCRIPT_DIR/fix-cloud-provider-taints.sh" "$INSTALL_DIR"; then
  echo "✅ Cloud provider taint check completed successfully"
else
  echo "⚠️  Cloud provider taint check had issues, but continuing..."
fi

# NEW: Wait for install completion after fixing taints
echo ""
echo "⏳ Waiting for installation to complete..."
cd "$INSTALL_DIR"

# Wait for install completion with our own timeout handling
INSTALL_PID=""
openshift-install wait-for install-complete --log-level=info &
INSTALL_PID=$!

# Wait for install with timeout (30 minutes = 1800 seconds)
TIMEOUT_SECONDS=1800
ELAPSED=0
INSTALL_EXIT_CODE=""

while [ $ELAPSED -lt $TIMEOUT_SECONDS ]; do
  if ! kill -0 $INSTALL_PID 2>/dev/null; then
    # Process has finished
    wait $INSTALL_PID
    INSTALL_EXIT_CODE=$?
    break
  fi
  sleep 30
  ELAPSED=$((ELAPSED + 30))
  echo "   Install wait progress: $ELAPSED/$TIMEOUT_SECONDS seconds..."
done

# Handle the result
if [ -n "$INSTALL_EXIT_CODE" ]; then
  if [ $INSTALL_EXIT_CODE -eq 0 ]; then
    echo "✅ Installation completed successfully!"
  else
    echo "❌ Installation failed with exit code $INSTALL_EXIT_CODE"
  fi
else
  # Timed out - kill the process
  echo "⚠️  Installation wait timed out, but cluster may still be completing..."
  echo "   Check cluster status manually with: oc get clusteroperators"
  kill $INSTALL_PID 2>/dev/null || true
  wait $INSTALL_PID 2>/dev/null || true
fi

cd "$SCRIPT_DIR"

echo ""
echo "🎉 Full rebuild complete with static IPs!"
echo "📋 Manifest backup available at: $BACKUP_DIR"

echo ""
echo "🔍 Verifying static IP injection..."
if cat "${INSTALL_DIR}/bootstrap.ign" | jq '.storage.files[] | select(.path | contains("system-connections"))' | grep -q "path"; then
  echo "✅ Static IP configuration found in bootstrap ignition file"
  
  # Show which IP was configured
  BOOTSTRAP_IP=$(cat "${INSTALL_DIR}/bootstrap.ign" | jq -r '.storage.files[] | select(.path | contains("system-connections")) | .contents.source' | sed 's/data:text\/plain;charset=utf-8;base64,//' | base64 -d | grep "address1=" | cut -d'=' -f2 | cut -d'/' -f1)
  echo "   Bootstrap IP configured as: $BOOTSTRAP_IP"
else
  echo "❌ Static IP configuration NOT found in bootstrap ignition file"
  echo "🔍 Check manifest backup at: $BACKUP_DIR"
fi

# Check individual ignition files
echo ""
echo "🔍 Verifying individual node ignition files..."
for node_type in master worker; do
  for i in 0 1 2; do
    if [ "$node_type" = "worker" ] && [ $i -gt 1 ]; then
      break
    fi
    
    IGN_FILE="${INSTALL_DIR}/${node_type}-${i}.ign"
    if [ -f "$IGN_FILE" ]; then
      if jq '.storage.files[] | select(.path | contains("system-connections"))' "$IGN_FILE" | grep -q "path"; then
        NODE_IP=$(jq -r '.storage.files[] | select(.path | contains("system-connections")) | .contents.source' "$IGN_FILE" | sed 's/data:text\/plain;charset=utf-8;base64,//' | base64 -d | grep "address1=" | cut -d'=' -f2 | cut -d'/' -f1)
        echo "✅ ${node_type}-${i}.ign: Static IP configured as $NODE_IP"
      else
        echo "❌ ${node_type}-${i}.ign: No static IP configuration found"
      fi
    else
      echo "⚠️  ${node_type}-${i}.ign: File not found"
    fi
  done
done

# NEW: Show final cluster status
echo ""
echo "🏁 Final cluster status:"
export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"
if oc cluster-info >/dev/null 2>&1; then
  echo "✅ Cluster API is accessible"
  echo "   Nodes:"
  oc get nodes -o wide 2>/dev/null || echo "   Unable to get node status"
  echo "   Cluster operators (showing any not ready):"
  oc get clusteroperators 2>/dev/null | head -1  # Header
  oc get clusteroperators 2>/dev/null | grep -v "True.*False.*False" | tail -n +2 || echo "   All cluster operators appear ready"
else
  echo "⚠️  Cluster API not accessible - check kubeconfig: $INSTALL_DIR/auth/kubeconfig"
fi