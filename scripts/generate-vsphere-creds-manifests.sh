#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Load govc credentials
source "${SCRIPT_DIR}/load-vcenter-env.sh"

# Verify manifests directory exists
MANIFESTS_DIR="${BASE_DIR}/install-configs/manifests"
mkdir -p "${MANIFESTS_DIR}"

# Base64 encode credentials
ENCODED_USERNAME=$(echo -n "$GOVC_USERNAME" | base64)
ENCODED_PASSWORD=$(echo -n "$GOVC_PASSWORD" | base64)

# Generate vsphere-creds secret manifest
cat > "${MANIFESTS_DIR}/vsphere-creds-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-creds
  namespace: openshift-machine-api
data:
  username: ${ENCODED_USERNAME}
  password: ${ENCODED_PASSWORD}
EOF

echo "✅ vSphere credentials secret manifest generated."
