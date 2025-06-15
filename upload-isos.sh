#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

CLUSTER_NAME="$(yq -r '.clusterName' "$CLUSTER_YAML")"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="${BASE_DIR}/assets/${CLUSTER_NAME}"

source "$BASE_DIR/govc.env"

: "${GOVC_DATASTORE:?GOVC_DATASTORE not set in govc.env}"

REMOTE_DIR="iso/${CLUSTER_NAME}"
echo "📁 Creating datastore folder: [$GOVC_DATASTORE] ${REMOTE_DIR}"
govc datastore.mkdir "${REMOTE_DIR}" || true

echo "📤 Uploading ISOs to [$GOVC_DATASTORE] ${REMOTE_DIR}"
for iso in "${ASSETS_DIR}"/*.iso; do
  echo "   → Uploading $(basename "$iso")"
  govc datastore.upload -ds="$GOVC_DATASTORE" "$iso" "${REMOTE_DIR}/$(basename "$iso")"
done

echo "✅ All ISOs uploaded to vSphere."
