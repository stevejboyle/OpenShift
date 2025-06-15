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

echo "💿 Creating Ignition config-drive ISOs in: $ASSETS_DIR"

create_iso() {
  local role="$1"
  local index="$2"
  local ign_file iso_file temp_dir

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

  temp_dir=$(mktemp -d)
  mkdir -p "${temp_dir}/ignition"
  cp "$ign_file" "${temp_dir}/ignition/config.ign"

  genisoimage -quiet -o "$iso_file" -V ignition -r -J "${temp_dir}/"

  rm -rf "$temp_dir"
  echo "   ✅ Created $iso_file"
}

# Bootstrap
create_iso bootstrap 0

# Masters
for i in 0 1 2; do
  create_iso master "$i"
done

# Optional workers
for i in 0 1; do
  ign_file="${INSTALL_DIR}/worker-${i}.ign"
  if [[ -f "$ign_file" ]]; then
    create_iso worker "$i"
  fi
done

echo "✅ All config-drive ISOs created."
