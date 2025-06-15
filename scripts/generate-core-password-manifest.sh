#!/usr/bin/env bash
set -euo pipefail
YAML="$1"
CLUSTER_NAME=$(yq -r '.clusterName' "$YAML")
INSTALL_DIR="install-configs/$CLUSTER_NAME/manifests"
HASH=$(cat "$(yq -r '.consolePasswordFile' "$YAML")")
mkdir -p "$INSTALL_DIR"
cat > "$INSTALL_DIR/99_core-user-password.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: core-user-password
  labels:
    machineconfiguration.openshift.io/role: master
spec:
  config:
    ignition:
      version: 3.2.0
    passwd:
      users:
      - name: core
        passwordHash: $HASH
EOF
