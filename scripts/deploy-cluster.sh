#!/bin/bash
set -e

CLUSTER_FILE=$1
if [ -z "$CLUSTER_FILE" ]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/load-vcenter-env.sh"

${SCRIPT_DIR}/generate-install-config.sh "$CLUSTER_FILE"

cd "${SCRIPT_DIR}/../install-configs"
openshift-install create ignition-configs

for VM in $(yq -r '.vms | keys[]' "$CLUSTER_FILE"); do
  ROLE="worker"
  [[ "$VM" == master* ]] && ROLE="master"
  [[ "$VM" == bootstrap ]] && ROLE="bootstrap"
  cp "${ROLE}.ign" "${VM}.ign"
done

${SCRIPT_DIR}/deploy-vms.sh "$CLUSTER_FILE"

