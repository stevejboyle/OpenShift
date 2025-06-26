#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster-yaml>"
  exit 1
fi

CLUSTER_NAME=$(yq -r '.clusterName' "$CLUSTER_YAML")
INSTALL_DIR="install-configs/${CLUSTER_NAME}"

echo "⏱ Starting OpenShift bootstrap monitoring for cluster: ${CLUSTER_NAME}"
echo "This process can take 15-30 minutes. Please be patient."

# The openshift-install wait-for bootstrap-complete command
# waits until the bootstrap process has successfully completed.
# It automatically retries and has a default timeout.
if openshift-install wait-for bootstrap-complete --dir="${INSTALL_DIR}"; then
  echo "✅ OpenShift bootstrap completed successfully!"
  exit 0
else
  echo "❌ OpenShift bootstrap failed or timed out."
  echo "   Please check the logs in ${INSTALL_DIR}/.openshift_install.log for details."
  exit 1
fi