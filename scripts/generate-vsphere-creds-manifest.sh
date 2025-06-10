#!/bin/zsh
set -e

source "$(dirname "$0")/load-vcenter-env.sh"
BASE_DIR="$(dirname "$(dirname "$0")")"
MANIFESTS_DIR="${BASE_DIR}/install-configs/manifests"
mkdir -p "${MANIFESTS_DIR}"

u=$(echo -n "$GOVC_USERNAME" | base64)
p=$(echo -n "$GOVC_PASSWORD" | base64)

cat > "${MANIFESTS_DIR}/vsphere-creds-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-creds
  namespace: openshift-machine-api
data:
  username: ${u}
  password: ${p}
EOF

echo "✅ vsphere-creds manifest generated."
