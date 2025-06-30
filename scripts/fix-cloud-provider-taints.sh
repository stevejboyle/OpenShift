#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Removing NoSchedule taint from master nodes..."
oc adm taint nodes -l node-role.kubernetes.io/master node-role.kubernetes.io/master:NoSchedule- || true
echo "✅ Taints removed from master nodes."

echo "🔧 Applying cloud provider labels to all nodes..."
for node in $(oc get nodes -o name); do
  oc label --overwrite $node 'node.cloudprovider.kubernetes.io/shutdown=false'
  oc label --overwrite $node 'node.openshift.io/os_id=rhcos'
done
echo "✅ Cloud provider labels applied."
