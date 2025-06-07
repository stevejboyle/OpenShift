#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/govc.env"

read -s -p "Enter vSphere password: " GOVC_PASSWORD
export GOVC_PASSWORD
echo ""

echo "🚀 Generating install-config.yaml..."
./generate-install-config.sh

echo "🚀 Generating Ignition configs..."
./run-install.sh

echo "🚀 Deploying vSphere VMs..."
./deploy-vms.sh

echo "🚀 Waiting for bootstrap to complete..."
openshift-install wait-for bootstrap-complete --dir=.

echo "✅ Bootstrap complete!"
echo ""
echo "⚠️  Manual action required:"
echo " - Shutdown and destroy bootstrap VM via govc or vSphere UI."
echo " - Then run:"
echo ""
echo "    openshift-install wait-for install-complete --dir=."
echo ""
