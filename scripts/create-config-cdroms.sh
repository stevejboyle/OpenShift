#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="${1:-}"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster-yaml>"
  exit 1
fi

if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

CLUSTER_NAME=$(yq eval '.clusterName' "$CLUSTER_YAML")
INSTALL_DIR="install-configs/${CLUSTER_NAME}"
ISO_OUTPUT_DIR="${INSTALL_DIR}/isos"

mkdir -p "$ISO_OUTPUT_DIR"

# Check for mkisofs or genisoimage
MKISOFS=$(command -v mkisofs || command -v genisoimage || true)
if [[ -z "$MKISOFS" ]]; then
  echo "❌ mkisofs or genisoimage not found. Please install one of them."
  exit 1
fi

echo "📀 Generating ISO config drives for each node..."

IGN_FILES=($(find "$INSTALL_DIR" -maxdepth 1 -name "*.ign"))

if [[ ${#IGN_FILES[@]} -eq 0 ]]; then
  echo "❌ No .ign files found in ${INSTALL_DIR}"
  exit 1
fi

# Add trap for temporary directory cleanup
# This ensures that the TEMP_DIR is removed even if the script exits unexpectedly.
TEMP_DIR_GLOBAL=$(mktemp -d)
trap "rm -rf '$TEMP_DIR_GLOBAL'" EXIT

for IGN in "${IGN_FILES[@]}"; do
  BASENAME=$(basename "$IGN" .ign)
  ISO_PATH="${ISO_OUTPUT_DIR}/${BASENAME}.iso"

  cp "$IGN" "${TEMP_DIR_GLOBAL}/config.ign"

  echo "   📦 Creating ISO for $BASENAME..."
  "$MKISOFS" -quiet -V config-2 -o "$ISO_PATH" -r "${TEMP_DIR_GLOBAL}/config.ign"

done

echo "✅ Config ISOs generated in: ${ISO_OUTPUT_DIR}"