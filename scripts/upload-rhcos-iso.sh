#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Usage: $0 <cluster-yaml>"
  exit 1
fi

SCRIPTS_DIR="$(dirname "$0")"

# Load vCenter environment variables
source "${SCRIPTS_DIR}/load-vcenter-env.sh"

# Extract RHCOS ISO filename from cluster YAML
RHCOS_ISO_FILENAME=$(yq -r '.rhcos_iso' "$CLUSTER_YAML")
# Construct the full local path to the RHCOS ISO
ISO_LOCAL="assets/${RHCOS_ISO_FILENAME}" # Assuming 'assets' is the base directory for your ISOs

# Construct the remote path on the datastore
CLUSTER_NAME=$(yq -r '.clusterName' "$CLUSTER_YAML")
REMOTE_PATH="iso/$CLUSTER_NAME-rhcos-live.iso" # This matches the path used in deploy-vms.sh (for the live ISO)

if [[ ! -f "$ISO_LOCAL" ]]; then
  echo "❌ Local RHCOS ISO not found: $ISO_LOCAL"
  exit 1
fi

# Check if the ISO already exists in the datastore
if ! govc datastore.stat "${GOVC_DATASTORE}/${REMOTE_PATH}" &>/dev/null; then
  echo "Uploading $ISO_LOCAL to ${GOVC_DATASTORE}/${REMOTE_PATH}..."
  govc datastore.upload "$ISO_LOCAL" "${GOVC_DATASTORE}/${REMOTE_PATH}"
  echo "✅ Uploaded ISO"
else
  echo "✅ ISO already exists in datastore: ${GOVC_DATASTORE}/${REMOTE_PATH}"
fi