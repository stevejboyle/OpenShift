#!/usr/bin/env bash
set -e

CLUSTER_YAML="$(realpath "$1")"
if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "❌ Cluster file not found: $1"
  exit 1
fi

# Get cluster name
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
BASE_DIR="$(dirname "$(dirname "$0")")"
MANIFESTS_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}/manifests"

# Use the same password file as console password
CONSOLE_PASSWORD_FILE=$(yq -r '.consolePasswordFile' "$CLUSTER_YAML")

# Resolve relative paths relative to the cluster YAML location
CLUSTER_DIR="$(dirname "$CLUSTER_YAML")"
if [[ ! "$CONSOLE_PASSWORD_FILE" = /* ]]; then
  CONSOLE_PASSWORD_FILE="${CLUSTER_DIR}/../${CONSOLE_PASSWORD_FILE}"
fi

if [[ ! -f "$CONSOLE_PASSWORD_FILE" ]]; then
  echo "❌ Console password file not found: $CONSOLE_PASSWORD_FILE"
  echo "This file should contain a password hash for both OpenShift console and core user access."
  exit 1
fi

# Read the password hash
PASSWORD_HASH=$(<"$CONSOLE_PASSWORD_FILE")
# Remove any trailing newlines
PASSWORD_HASH=$(echo "$PASSWORD_HASH" | tr -d '\n')

echo "🔑 Generating core user password manifests for cluster ${CLUSTER_NAME}..."

# Create manifests directory if it doesn't exist
mkdir -p "${MANIFESTS_DIR}"

# Create MachineConfig for bootstrap nodes
cat > "${MANIFESTS_DIR}/99-core-user-password-bootstrap.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: bootstrap
  name: 99-core-user-password-bootstrap
spec:
  config:
    ignition:
      version: 3.2.0
    passwd:
      users:
      - name: core
        passwordHash: "${PASSWORD_HASH}"
EOF

# Create MachineConfig for master nodes
cat > "${MANIFESTS_DIR}/99-core-user-password-master.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-core-user-password-master
spec:
  config:
    ignition:
      version: 3.2.0
    passwd:
      users:
      - name: core
        passwordHash: "${PASSWORD_HASH}"
EOF

# Create MachineConfig for worker nodes
cat > "${MANIFESTS_DIR}/99-core-user-password-worker.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-core-user-password-worker
spec:
  config:
    ignition:
      version: 3.2.0
    passwd:
      users:
      - name: core
        passwordHash: "${PASSWORD_HASH}"
EOF

echo "✅ Core user password manifests generated:"
echo "   - Bootstrap nodes: 99-core-user-password-bootstrap.yaml"
echo "   - Master nodes: 99-core-user-password-master.yaml"
echo "   - Worker nodes: 99-core-user-password-worker.yaml"
echo ""
echo "📝 Using the same password hash for both OpenShift admin and core user console access."
echo "   - OpenShift console: admin / [your password]"
echo "   - Node console: core / [your password]"
