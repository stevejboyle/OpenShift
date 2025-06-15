#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

CLUSTER_NAME="$(yq -r '.clusterName' "$CLUSTER_YAML")"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}"
ASSETS_DIR="${BASE_DIR}/assets/${CLUSTER_NAME}"

mkdir -p "$ASSETS_DIR"

echo "📦 Generating ISO images for ignition configs in $INSTALL_DIR..."

for node in bootstrap master-0 master-1 master-2 worker-0 worker-1; do
  IGN_FILE="${INSTALL_DIR}/${node}.ign"
  ISO_PATH="${ASSETS_DIR}/${node}.iso"

  if [[ -f "$IGN_FILE" ]]; then
    echo "   → Creating ISO for ${node}"
    mkisofs -output "$ISO_PATH" -volid config-2 -joliet -rock "$IGN_FILE"
  else
    echo "   ⚠️  Skipping ${node} — ignition file not found: $IGN_FILE"
  fi
done

echo "✅ All available ignition ISOs generated in: $ASSETS_DIR"
