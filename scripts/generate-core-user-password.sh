#!/usr/bin/env bash
set -euo pipefail

YAML="$1"
if [[ -z "$YAML" || ! -f "$YAML" ]]; then
  echo "❌ Usage: $0 <cluster-yaml>"
  exit 1
fi

CLUSTER_NAME=$(yq -r '.clusterName' "$YAML")
INSTALL_DIR="install-configs/$CLUSTER_NAME/manifests"
# Assuming 'consolePasswordFile' from YAML might contain the core user's password hash
PASSWORD_HASH_FILE=$(yq -r '.consolePasswordFile' "$YAML") # Or create a dedicated 'coreUserPasswordFile' in YAML

if [[ ! -f "$PASSWORD_HASH_FILE" ]]; then
  echo "❌ Core user password hash file not found: $PASSWORD_HASH_FILE"
  echo "   Please ensure '$PASSWORD_HASH_FILE' exists and contains the core user's password hash (e.g., from 'mkpasswd -m sha512')."
  exit 1
fi

HASH=$(cat "$PASSWORD_HASH_FILE")
mkdir -p "$INSTALL_DIR"

echo "🔐 Generating MachineConfig to set 'core' user password..."

cat > "$INSTALL_DIR/99_core-user-password.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: core-user-password
  labels:
    machineconfiguration.openshift.io/role: master # Apply to master nodes by default
spec:
  config:
    ignition:
      version: 3.2.0
    passwd:
      users:
      - name: core
        passwordHash: ${HASH}
EOF

echo "✅ MachineConfig for 'core' user password created in: ${INSTALL_DIR}/99_core-user-password.yaml"
