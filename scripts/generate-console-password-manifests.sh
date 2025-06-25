#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="${1:-}"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster-yaml>"
  exit 1
fi

if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML file not found: $CLUSTER_YAML"
  exit 1
fi

# Extract cluster name
CLUSTER_NAME=$(yq eval '.clusterName' "$CLUSTER_YAML")
INSTALL_DIR="install-configs/${CLUSTER_NAME}"
PASSWORD_FILE=$(yq eval '.consolePasswordFile' "$CLUSTER_YAML")

if [[ ! -f "$PASSWORD_FILE" ]]; then
  echo "❌ Console password hash file not found: $PASSWORD_FILE"
  exit 1
fi

echo "🔐 Generating admin password secret for web console..."

mkdir -p "${INSTALL_DIR}/manifests"

cat > "${INSTALL_DIR}/manifests/99_openshift-cluster-admin-password-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: htpasswd-secret
  namespace: openshift-config
type: Opaque
stringData:
  htpasswd: |
    admin:$(cat "$PASSWORD_FILE")
EOF

cat > "${INSTALL_DIR}/manifests/99_openshift-cluster-admin-oauth.yaml" <<EOF
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd-secret
EOF

echo "✅ Console password manifests created in: ${INSTALL_DIR}/manifests"

