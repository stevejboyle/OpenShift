#!/usr/bin/env bash
# Set a tiny inline Ignition (config.replace -> URL) via guestinfo.data/base64
# Usage: set-ignition-replace.sh <vm-ipath> <http-url-to-real-ign>
set -euo pipefail
VM_IPATH="$1"
IGN_URL="$2"

if [[ -z "${VM_IPATH:-}" || -z "${IGN_URL:-}" ]]; then
  echo "Usage: $0 <vm-ipath> <http-url-to-real-ign>"
  exit 1
fi

MIN_IGN=$(cat <<JSON
{"ignition":{"version":"3.4.0","config":{"replace":{"source":"${IGN_URL}"}}}}
JSON
)

B64=$(printf "%s" "$MIN_IGN" | base64 | tr -d '\n')

govc vm.change -vm.ipath "$VM_IPATH" \
  -e "guestinfo.ignition.config.data=${B64}" \
  -e "guestinfo.ignition.config.data.encoding=base64" \
  -e "guestinfo.ignition.config.url="

# Show result
govc vm.info -e -vm.ipath "$VM_IPATH" | grep -E 'guestinfo\.ignition|guestinfo\.kernel' || true
