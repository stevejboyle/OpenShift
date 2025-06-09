#!/bin/zsh
set -e

CLUSTER_FILE=$1
if [ -z "$CLUSTER_FILE" ]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Verify consolePasswordFile exists
CONSOLE_PASSWORD_FILE=$(yq '.consolePasswordFile' "$CLUSTER_FILE")
if [ ! -f "$CONSOLE_PASSWORD_FILE" ]; then
  echo "❌ consolePasswordFile not found: ${CONSOLE_PASSWORD_FILE}"
  exit 1
fi

# Read the existing hashed password
PASSWORD_HASH=$(cat "$CONSOLE_PASSWORD_FILE")

# Verify manifests directory exists
MANIFESTS_DIR="${BASE_DIR}/install-configs/manifests"
mkdir -p "${MANIFESTS_DIR}"

# Create master manifest
cat > "${MANIFESTS_DIR}/99-master-console-password.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-master-console-password
  labels:
    machineconfiguration.openshift.io/role: master
spec:
  config:
    ignition:
      version: 3.2.0
    passwd:
      users:
        - name: core
          passwordHash: "${PASSWORD_HASH}"
EOF

# Create worker manifest
cat > "${MANIFESTS_DIR}/99-worker-console-password.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-worker-console-password
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.2.0
    passwd:
      users:
        - name: core
          passwordHash: "${PASSWORD_HASH}"
EOF

echo "✅ Console password manifests generated successfully."
