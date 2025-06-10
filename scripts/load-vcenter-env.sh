#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Load govc.env
if [[ ! -f "${BASE_DIR}/govc.env" ]]; then
  echo "❌ govc.env not found in ${BASE_DIR}"
  exit 1
fi
source "${BASE_DIR}/govc.env"

# Prompt for password if not already set
if [[ -z "$GOVC_PASSWORD" ]]; then
  echo "🔐 Enter vSphere password for ${GOVC_USERNAME}:"
  read -s GOVC_PASSWORD
  export GOVC_PASSWORD
fi
