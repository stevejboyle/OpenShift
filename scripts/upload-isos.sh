#!/usr/bin/env bash
set -euo pipefail

YAML="$1"
CLUSTER_NAME=$(yq -r '.clusterName' "$YAML")
ISO_LOCAL="assets/rhcos-live.iso"
REMOTE_PATH="iso/$CLUSTER_NAME-rhcos-live.iso"

if ! govc datastore.stat "$REMOTE_PATH" &>/dev/null; then
  echo "Uploading $ISO_LOCAL to $REMOTE_PATH..."
  govc datastore.upload "$ISO_LOCAL" "$REMOTE_PATH"
  echo "✅ Uploaded ISO"
else
  echo "✅ ISO already exists in datastore"
fi
