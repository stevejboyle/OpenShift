#!/usr/bin/env bash
set -e

CLUSTER_NAME="$1"
if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name>"
  exit 1
fi

# Get the script directory and base directory correctly
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

source "${SCRIPT_DIR}/load-vcenter-env.sh"

# Check if password is available, prompt if not
if [[ -z "${GOVC_PASSWORD:-}" ]]; then
  echo -n "🔐 GOVC_PASSWORD not set. Enter vSphere password for $GOVC_USERNAME: "
  read -s GOVC_PASSWORD
  echo
  export GOVC_PASSWORD
fi

# Validate that credentials are loaded
if [[ -z "$GOVC_USERNAME" || -z "$GOVC_PASSWORD" ]]; then
  echo "❌ GOVC credentials not loaded properly"
  exit 1
fi

# Use the correct path structure
MANIFESTS_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}/manifests"
mkdir -p "${MANIFESTS_DIR}"

u=$(echo -n "$GOVC_USERNAME" | base64 -w0)
p=$(echo -n "$GOVC_PASSWORD" | base64 -w0)

echo "🔐 Creating vSphere credentials secrets..."

# 1. Create the primary secret (for UPI machine manifests)
cat > "${MANIFESTS_DIR}/vsphere-creds-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-creds
  namespace: openshift-machine-api
type: Opaque
data:
  username: ${u}
  password: ${p}
EOF

# 2. Create the cloud-credential-operator expected secret format
cat > "${MANIFESTS_DIR}/vsphere-cloud-credentials-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-cloud-credentials
  namespace: openshift-machine-api
type: Opaque
data:
  ${GOVC_URL#https://}.username: ${u}
  ${GOVC_URL#https://}.password: ${p}
EOF

# 3. Create the source secret for cloud-credential-operator
cat > "${MANIFESTS_DIR}/vsphere-source-credentials-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-cloud-credentials
  namespace: openshift-cloud-credential-operator
type: Opaque
data:
  ${GOVC_URL#https://}.username: ${u}
  ${GOVC_URL#https://}.password: ${p}
EOF

# 4. Override the cloud-credential-operator CredentialsRequest to use manual mode
cat > "${MANIFESTS_DIR}/99-disable-vsphere-credentials-request.yaml" <<EOF
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  name: openshift-machine-api-vsphere
  namespace: openshift-cloud-credential-operator
  annotations:
    cloudcredential.openshift.io/mode: manual
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: VSphereProviderSpec
  secretRef:
    name: vsphere-cloud-credentials
    namespace: openshift-machine-api
EOF

echo "✅ All vSphere credentials manifests generated for cluster ${CLUSTER_NAME}:"
echo "📍 Primary secret: ${MANIFESTS_DIR}/vsphere-creds-secret.yaml"
echo "📍 Cloud-credential secret: ${MANIFESTS_DIR}/vsphere-cloud-credentials-secret.yaml" 
echo "📍 Source secret: ${MANIFESTS_DIR}/vsphere-source-credentials-secret.yaml"
echo "📍 Manual mode override: ${MANIFESTS_DIR}/99-disable-vsphere-credentials-request.yaml"
echo ""
echo "🎯 This covers all possible secret name references and disables automatic credential management."
