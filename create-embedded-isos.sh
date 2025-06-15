#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "❌ Cluster file not found: $CLUSTER_YAML"
  exit 1
fi

CLUSTER_NAME="$(yq -r '.clusterName' "$CLUSTER_YAML")"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}"
ASSETS_DIR="${BASE_DIR}/assets/${CLUSTER_NAME}"

mkdir -p "$ASSETS_DIR"

echo "📦 Generating embedded ISO images for cluster: $CLUSTER_NAME"
echo "   Output directory: $ASSETS_DIR"

create_iso() {
  local role="$1"
  local index="$2"
  local ign_file iso_file

  if [[ "$role" == "bootstrap" ]]; then
    ign_file="${INSTALL_DIR}/bootstrap.ign"
    iso_file="${ASSETS_DIR}/bootstrap.iso"
  else
    ign_file="${INSTALL_DIR}/${role}-${index}.ign"
    iso_file="${ASSETS_DIR}/${role}-${index}.iso"
  fi

  if [[ ! -f "$ign_file" ]]; then
    echo "⚠️  Ignition file not found: $ign_file"
    return
  fi

  echo "   🔧 Embedding $ign_file into $iso_file"
  coreos-installer iso ignition embed -i "$ign_file" -o "$iso_file" /usr/local/share/openshift/rhcos-live.x86_64.iso
}

# Bootstrap
create_iso bootstrap 0

# Masters
for i in 0 1 2; do
  create_iso master "$i"
done

# Optional workers (0 and 1)
for i in 0 1; do
  ign_file="${INSTALL_DIR}/worker-${i}.ign"
  if [[ -f "$ign_file" ]]; then
    create_iso worker "$i"
  fi
done

echo "✅ Embedded ISOs created in: $ASSETS_DIR"
