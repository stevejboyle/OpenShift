#!/usr/bin/env bash
set -e

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

# Get cluster name and password file
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
pwf=$(yq '.consolePasswordFile' "$CLUSTER_YAML")

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
  echo "⚠ No console-password file defined; skipping."
fi
