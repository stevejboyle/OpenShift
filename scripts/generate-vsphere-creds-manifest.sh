#!/usr/bin/env bash
set -euo pipefail
CLUSTER_NAME="$1"
INSTALL_DIR="install-configs/$CLUSTER_NAME/manifests"
mkdir -p "$INSTALL_DIR"
echo "Generating dummy vSphere creds secret manifest..."
cat > "$INSTALL_DIR/vsphere-creds.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-cloud-credentials
  namespace: openshift-machine-api
data:
  username: BASE64_USERNAME
  password: BASE64_PASSWORD
EOF
