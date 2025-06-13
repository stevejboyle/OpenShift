#!/usr/bin/env bash
# Simple environment loader - no parameters needed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Load govc environment
if [[ -f "${BASE_DIR}/govc.env" ]]; then
  source "${BASE_DIR}/govc.env"
  echo "✅ vCenter environment loaded from govc.env"
else
  echo "❌ govc.env not found at ${BASE_DIR}/govc.env"
  exit 1
fi

# Validate required variables
if [[ -z "$GOVC_URL" || -z "$GOVC_USERNAME" ]]; then
  echo "❌ Required GOVC environment variables not set"
  exit 1
fi

# NEW: Validate username format
if [[ ! "$GOVC_USERNAME" =~ @.*\. ]]; then
  echo "⚠️  Username should be in format user@domain.tld (current: $GOVC_USERNAME)"
fi

# NEW: Check if password is set
if [[ -z "${GOVC_PASSWORD:-}" ]]; then
  echo "⚠️  GOVC_PASSWORD not set - will need to be provided when needed"
fi

echo "📋 Loaded credentials for: $GOVC_USERNAME @ $(echo $GOVC_URL | sed 's|https://||')"
