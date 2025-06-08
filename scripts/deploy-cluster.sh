#!/bin/bash
set -e

CLUSTER_FILE=$1
if [ -z "$CLUSTER_FILE" ]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Generate install-config.yaml
${SCRIPT_DIR}/generate-install-config.sh "$CLUSTER_FILE"

# Create ignition configs
cd "${SCRIPT_DIR}/../install-configs"
openshift-install create ignition-configs

# Copy per-role ignition to per-VM ignition files
for VM in $(yq -r '.vms | keys[]' "$CLUSTER_FILE"); do
  ROLE="worker"
  [[ "$VM" == master* ]] && ROLE="master"
  [[ "$VM" == bootstrap ]] && ROLE="bootstrap"
  cp "${ROLE}.ign" "${VM}.ign"
done

# Deploy VMs
${SCRIPT_DIR}/deploy-vms.sh "$CLUSTER_FILE"
