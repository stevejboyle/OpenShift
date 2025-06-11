#!/usr/bin/env bash
set -e

CLUSTER_NAME="$1"
if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name>"
  exit 1
fi

# Get the script directory and base directory correctly
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

source "${SCRIPT_DIR}/load-vcenter-env.sh"

# Check if password is available, prompt if not
if [[ -z "${GOVC_PASSWORD:-}" ]]; then
  echo -n "🔐 GOVC_PASSWORD not set. Enter vSphere password for $GOVC_USERNAME: "
  read -s GOVC_PASSWORD
  echo
  export GOVC_PASSWORD
fi

# Validate that credentials are loaded
if [[ -z "$GOVC_USERNAME" || -z "$GOVC_PASSWORD" ]]; then
  echo "❌ GOVC credentials not loaded properly"
  exit 1
fi

# Use the correct path structure
MANIFESTS_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}/manifests"
mkdir -p "${MANIFESTS_DIR}"

u=$(echo -n "$GOVC_USERNAME" | base64 -w0)
p=$(echo -n "$GOVC_PASSWORD" | base64 -w0)

cat > "${MANIFESTS_DIR}/vsphere-creds-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-creds
  namespace: openshift-machine-api
type: Opaque
data:
  username: ${u}
  password: ${p}
EOF

echo "✅ vsphere-creds manifest generated for cluster ${CLUSTER_NAME}."
echo "📍 Location: ${MANIFESTS_DIR}/vsphere-creds-secret.yaml"
