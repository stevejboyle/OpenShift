#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="$1"
export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"
echo "Checking for cloud provider taints..."
for node in $(oc get nodes -o name); do
  if oc describe "$node" | grep -q "node.cloudprovider.kubernetes.io/uninitialized"; then
    echo "Removing taint from $node"
    oc adm taint nodes "$node" node.cloudprovider.kubernetes.io/uninitialized:NoSchedule-
  fi
done
