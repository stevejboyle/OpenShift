#!/usr/bin/env bash
set -euo pipefail

# This script loads and exports vCenter credentials and connection info from govc.env
# It also performs validation to ensure the credentials are usable.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
GOVC_ENV_FILE="$BASE_DIR/govc.env"

if [ ! -f "$GOVC_ENV_FILE" ]; then
  echo "❌ govc.env not found at: $GOVC_ENV_FILE"
  exit 1
fi

# Load environment variables
set -a
source "$GOVC_ENV_FILE"
set +a

if [ -z "${GOVC_USERNAME:-}" ]; then
  echo "❌ GOVC_USERNAME is not set in govc.env"
  exit 1
fi

# Prompt for vSphere password securely if not already set
if [ -z "${GOVC_PASSWORD:-}" ]; then
  echo -n "🔐 Enter vSphere password for $GOVC_USERNAME: "
  read -s GOVC_PASSWORD
  echo
fi

export GOVC_PASSWORD
export VSPHERE_USERNAME="$GOVC_USERNAME"
export VSPHERE_PASSWORD="$GOVC_PASSWORD"

# Optional: Validate connection
if ! govc about >/dev/null 2>&1; then
  echo "❌ Unable to connect to vCenter: $GOVC_URL"
  echo "   Please verify GOVC_URL, GOVC_USERNAME, and GOVC_PASSWORD"
  exit 1
fi

echo "✅ Successfully loaded and validated vSphere credentials"
