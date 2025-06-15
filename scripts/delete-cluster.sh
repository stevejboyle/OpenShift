#!/usr/bin/env bash
set -eo pipefail

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "❌ Usage: $0 <cluster-yaml>"
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_CONFIG_DIR="${SCRIPTS_DIR}/../install-configs"
CLUSTER_NAME="$(basename "$CLUSTER_YAML" .yaml)"
CLUSTER_DIR="${INSTALL_CONFIG_DIR}/${CLUSTER_NAME}"

source "${SCRIPTS_DIR}/load-vcenter-env.sh"

# Clean up previous artifacts
"${SCRIPTS_DIR}/delete-cluster.sh" "$CLUSTER_YAML"

# Generate install-config.yaml
"${SCRIPTS_DIR}/generate-install-config.sh" "$CLUSTER_YAML"

# Generate manifests
mkdir -p "$CLUSTER_DIR"
cp "${CLUSTER_DIR}/install-config.yaml" .
openshift-install create manifests --dir "$CLUSTER_DIR" || echo "⚠️  Proceeding despite manifest warnings..."

# Inject vSphere credentials manifest
"${SCRIPTS_DIR}/generate-vsphere-creds-manifest.sh" "$CLUSTER_YAML"
cp manifests/* "$CLUSTER_DIR/manifests/"
cp openshift/* "$CLUSTER_DIR/manifests/"

# Generate static IP manifests and ignition files
"${SCRIPTS_DIR}/generate-static-ip-manifests.sh" "$CLUSTER_YAML"
"${SCRIPTS_DIR}/create-individual-node-ignitions.sh" "$CLUSTER_YAML"

# Deploy the VMs
"${SCRIPTS_DIR}/deploy-vms.sh" "$CLUSTER_YAML"

# Wait for bootstrap
openshift-install wait-for bootstrap-complete --dir "$CLUSTER_DIR" --log-level debug

# Fix cloud provider issues
"${SCRIPTS_DIR}/fix-cloud-provider-taints.sh" "$CLUSTER_DIR"

# Wait for install completion
openshift-install wait-for install-complete --dir "$CLUSTER_DIR" --log-level debug
