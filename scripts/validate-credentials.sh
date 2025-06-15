#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(dirname "$0")"
source "${SCRIPTS_DIR}/load-vcenter-env.sh"

echo "🔐 Validating vSphere credentials..."

if [[ -z "${GOVC_USERNAME:-}" ]] || [[ -z "${GOVC_PASSWORD:-}" ]]; then
  echo "❌ GOVC_USERNAME or GOVC_PASSWORD not set. Check your environment."
  exit 1
fi

if ! govc about &>/dev/null; then
  echo "❌ Cannot connect to vCenter: $GOVC_URL"
  echo "   Check your GOVC credentials and network access."
  exit 1
fi

echo "✅ Connected to vCenter: $GOVC_URL"
echo "👤 User: $GOVC_USERNAME"

# Check for proper username format (e.g., administrator@vsphere.local)
if [[ "$GOVC_USERNAME" != *@*.* ]]; then
  echo "⚠️  Warning: Username may be in an invalid format: $GOVC_USERNAME"
  echo "   Expected format: user@domain.tld"
else
  echo "✅ Username format appears valid"
fi

# Check for access to required resources
MISSING=0
for RESOURCE in "$GOVC_DATACENTER" "$GOVC_CLUSTER" "$GOVC_DATASTORE" "$GOVC_NETWORK"; do
  if ! govc ls "$RESOURCE" &>/dev/null; then
    echo "❌ Cannot access vSphere resource: $RESOURCE"
    MISSING=1
  else
    echo "✅ Found resource: $RESOURCE"
  fi
done

if [[ "$MISSING" -ne 0 ]]; then
  echo "❌ One or more required vSphere resources are inaccessible."
  exit 1
fi

echo "🎉 vSphere credential validation successful!"
