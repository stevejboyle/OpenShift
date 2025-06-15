#!/usr/bin/env bash
set -euo pipefail

# fix-cloud-provider-taints.sh
# Removes cloud provider initialization taints that can prevent pods from scheduling
# during OpenShift cluster bootstrap on vSphere

INSTALL_DIR="${1:-}"
if [ -z "$INSTALL_DIR" ]; then
  echo "❌ Usage: $0 <install-dir>"
  exit 1
fi

KUBECONFIG_PATH="$INSTALL_DIR/auth/kubeconfig"

if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "❌ Kubeconfig not found: $KUBECONFIG_PATH"
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

echo "🔍 Waiting for cluster API to be available..."
# Wait for cluster API to be responsive
max_api_wait=300  # 5 minutes
api_wait=0
while ! oc cluster-info --request-timeout=10s >/dev/null 2>&1; do
  if [ $api_wait -ge $max_api_wait ]; then
    echo "❌ Cluster API not available after $max_api_wait seconds"
    exit 1
  fi
  echo "   Cluster API not ready yet, waiting... ($api_wait/$max_api_wait)"
  sleep 10
  ((api_wait+=10))
done
echo "✅ Cluster API is available"

echo "🔍 Waiting for nodes to be available..."
# Wait for nodes to be available
max_node_wait=600  # 10 minutes
node_wait=0
while [ $(oc get nodes --no-headers 2>/dev/null | wc -l) -eq 0 ]; do
  if [ $node_wait -ge $max_node_wait ]; then
    echo "❌ No nodes found after $max_node_wait seconds"
    exit 1
  fi
  echo "   No nodes found yet, waiting... ($node_wait/$max_node_wait)"
  sleep 30
  ((node_wait+=30))
done

NODE_COUNT=$(oc get nodes --no-headers | wc -l)
echo "✅ Found $NODE_COUNT nodes"

echo "🔍 Checking for cloud provider initialization taints..."
# Check for and remove cloud provider initialization taints
TAINTED_NODES=$(oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints[?(@.key=="node.cloudprovider.kubernetes.io/uninitialized")].key}{"\n"}{end}' 2>/dev/null | grep uninitialized | cut -f1 || true)

if [ ! -z "$TAINTED_NODES" ]; then
  echo "⚠️  Found nodes with cloud provider initialization taints:"
  echo "$TAINTED_NODES"
  echo "🔧 Removing taints..."
  
  for node in $TAINTED_NODES; do
    echo "   Removing taint from $node"
    if oc adm taint nodes "$node" node.cloudprovider.kubernetes.io/uninitialized:NoSchedule- 2>/dev/null; then
      echo "   ✅ Successfully removed taint from $node"
    else
      echo "   ⚠️  Taint removal failed or taint doesn't exist on $node"
    fi
  done
  
  echo "⏱️  Waiting 60 seconds for pods to schedule..."
  sleep 60
else
  echo "✅ No cloud provider initialization taints found"
fi

echo "🔍 Waiting for critical pods to be running..."

# Wait for etcd-operator to be running
echo "   Waiting for etcd-operator..."
if oc wait --for=condition=Ready pod -l app=etcd-operator -n openshift-etcd-operator --timeout=300s 2>/dev/null; then
  echo "   ✅ etcd-operator is running"
else
  echo "   ⚠️  etcd-operator not ready within timeout, but continuing..."
  # Show current status for debugging
  oc get pods -n openshift-etcd-operator -l app=etcd-operator 2>/dev/null || true
fi

# Wait for cloud-credential-operator to be running
echo "   Waiting for cloud-credential-operator..."
if oc wait --for=condition=Ready pod -l app=cloud-credential-operator -n openshift-cloud-credential-operator --timeout=300s 2>/dev/null; then
  echo "   ✅ cloud-credential-operator is running"
else
  echo "   ⚠️  cloud-credential-operator not ready within timeout, but continuing..."
  # Show current status for debugging
  oc get pods -n openshift-cloud-credential-operator -l app=cloud-credential-operator 2>/dev/null || true
fi

echo "🔍 Current cluster status:"
echo "   Nodes:"
oc get nodes -o wide 2>/dev/null || echo "   Unable to get node status"

echo "   Critical pods:"
oc get pods -n openshift-etcd-operator -l app=etcd-operator 2>/dev/null || echo "   Unable to get etcd-operator status"
oc get pods -n openshift-cloud-credential-operator -l app=cloud-credential-operator 2>/dev/null || echo "   Unable to get cloud-credential-operator status"

echo "✅ Cloud provider taint check and critical pod verification complete"
