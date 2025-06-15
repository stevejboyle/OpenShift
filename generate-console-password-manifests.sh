#!/usr/bin/env bash
set -e

CLUSTER_YAML="$(realpath "$1")"
if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "❌ Cluster file not found: $1"
  exit 1
fi

# Get cluster name and password file
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
pwf=$(yq -r '.consolePasswordFile' "$CLUSTER_YAML")

# Resolve relative paths relative to the cluster YAML location
CLUSTER_DIR="$(dirname "$CLUSTER_YAML")"
if [[ ! "$pwf" = /* ]]; then
  pwf="${CLUSTER_DIR}/../${pwf}"
fi

if [[ -f "$pwf" ]]; then
  h=$(<"$pwf")
  BASE_DIR="$(dirname "$(dirname "$0")")"
  MANIFESTS_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}/manifests"
  mkdir -p "${MANIFESTS_DIR}"

  # Create htpasswd identity provider for console access
  cat > "${MANIFESTS_DIR}/99-console-htpasswd.yaml" <<EOF
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpasswd
    type: HTPasswd
    mappingMethod: claim
    htpasswd:
      fileData:
        name: htpasswd-secret
---
apiVersion: v1
kind: Secret
metadata:
  name: htpasswd-secret
  namespace: openshift-config
type: Opaque
data:
  htpasswd: $(echo -n "admin:${h}" | base64 -w0)
EOF

  # Also create cluster admin role binding
  cat > "${MANIFESTS_DIR}/99-admin-user.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: admin
EOF

  echo "✅ Console password manifests generated for cluster ${CLUSTER_NAME}."
else
  echo "⚠ No console-password file found at: $pwf; skipping."
fi
