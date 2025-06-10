#!/bin/bash
set -e

# Builder for Deployment Kit v2.0 Final
BASE="deployment-kit-v2.0-final"
ZIP="${BASE}.zip"

# Clean up any previous run
rm -rf "$BASE" "$ZIP"
mkdir -p "$BASE"/{assets,clusters,scripts,install-configs}

# .gitignore
cat > "$BASE/.gitignore" <<EOF
# Ignore sensitive and generated files
assets/*
!assets/
install-configs/
__MACOSX/
.DS_Store
EOF

# clusters/ocp416.yaml (flat model)
cat > "$BASE/clusters/ocp416.yaml" <<EOF
clusterName: ocp416
baseDomain: openshift.sboyle.internal
vcenter_server: vcenter1.sboyle.internal
vcenter_username: administrator@vsphere.sboyle.internal
vcenter_password: SuperSecret123
vcenter_datacenter: Lab
vcenter_cluster: Lab Cluster
vcenter_datastore: datastore-SAN1
vcenter_network: OpenShift_192.168.42.0
sshKeyFile: assets/ssh-key.pub
pullSecretFile: assets/pull-secret.json
consolePasswordFile: assets/console-password.txt
EOF

# load-vcenter-env.sh
cat > "$BASE/scripts/load-vcenter-env.sh" <<'EOS'
#!/bin/zsh
set -e
source "$(dirname "$0")/../govc.env"
if [ -z "$GOVC_PASSWORD" ]; then
  echo "Enter vSphere password for $GOVC_USERNAME:"
  read -s GOVC_PASSWORD
  export GOVC_PASSWORD
fi
EOS

# generate-install-config.sh
cat > "$BASE/scripts/generate-install-config.sh" <<'EOS'
#!/bin/zsh
set -e
CLUSTER_YAML="$1"
if [ ! -f "$CLUSTER_YAML" ]; then
  echo "Usage: $0 clusters/ocp416.yaml"
  exit 1
fi
source "$(dirname "$0")/load-vcenter-env.sh"
baseDir="$(dirname "$(dirname "$0")")"
mkdir -p "$baseDir/install-configs"
cn=$(yq '.clusterName' "$CLUSTER_YAML")
bd=$(yq '.baseDomain' "$CLUSTER_YAML")
vc=$(yq '.vcenter_server' "$CLUSTER_YAML")
un=$(yq '.vcenter_username' "$CLUSTER_YAML")
pw=$(yq '.vcenter_password' "$CLUSTER_YAML")
dc=$(yq '.vcenter_datacenter' "$CLUSTER_YAML")
cl=$(yq '.vcenter_cluster' "$CLUSTER_YAML")
ds=$(yq '.vcenter_datastore' "$CLUSTER_YAML")
nw=$(yq '.vcenter_network' "$CLUSTER_YAML")
sk=$(<"$(yq '.sshKeyFile' "$CLUSTER_YAML")")
ps=$(<"$(yq '.pullSecretFile' "$CLUSTER_YAML")")
cp="/$dc/host/$cl"
dsp="/$dc/datastore/$ds"
cat > "$baseDir/install-configs/install-config.yaml" <<EOF
apiVersion: v1
baseDomain: $bd
metadata:
  name: $cn
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 3
platform:
  vsphere:
    vcenters:
    - name: primary-vcenter
      server: $vc
      username: $un
      password: $pw
      datacenters:
      - $dc
    failureDomains:
    - name: primary
      region: region-a
      zone: zone-a
      server: $vc
      topology:
        datacenter: $dc
        computeCluster: $cp
        datastore: $dsp
        networks:
        - $nw
networking:
  machineNetwork:
  - cidr: $(yq '.network.cidr' "$CLUSTER_YAML")
  networkType: OVNKubernetes
pullSecret: |
  $ps
sshKey: |
  $sk
EOF
EOF
chmod +x "$BASE/scripts/generate-install-config.sh"

# deploy-cluster.sh
cat > "$BASE/scripts/deploy-cluster.sh" <<'EOS'
#!/bin/zsh
set -e
CLUSTER_FILE=$1
if [ -z "$CLUSTER_FILE" ]; then echo "Usage: $0 <cluster.yaml>"; exit 1; fi
source "$(dirname "$0")/load-vcenter-env.sh"
$(dirname "$0")/generate-install-config.sh "$CLUSTER_FILE"
cd "$(dirname "$0")/../install-configs"
openshift-install create manifests
cd "$(dirname "$0")/.."
$(dirname "$0")/generate-vsphere-creds-manifest.sh
$(dirname "$0")/generate-console-password-manifests.sh "$CLUSTER_FILE"
cd "$(dirname "$0")/../install-configs"
export OPENSHIFT_INSTALL_EXPERIMENTAL_OVERRIDES='{ "disableTemplatedInstallConfig": true }'
openshift-install create ignition-configs
cd "$(dirname "$0")/.."
$(dirname "$0")/deploy-vms.sh "$CLUSTER_FILE"
EOS
chmod +x "$BASE/scripts/deploy-cluster.sh"

# deploy-vms.sh
cat > "$BASE/scripts/deploy-vms.sh" <<'EOS'
#!/bin/zsh
set -e
CLUSTER_FILE=$1
if [ -z "$CLUSTER_FILE" ]; then echo "Usage: $0 <cluster.yaml>"; exit 1; fi
source "$(dirname "$0")/load-vcenter-env.sh"
baseDir="$(dirname "$(dirname "$0")")"
ova="$baseDir/assets/rhcos-4.16.36-x86_64-vmware.x86_64.ova"
vmfld=$(yq '.vcenter_folder' "$CLUSTER_FILE")
vmnet=$(yq '.vcenter_network' "$CLUSTER_FILE")
if ! govc ls "$vmfld/rhcos-template" &>/dev/null; then
  govc import.ova -name rhcos-template -folder "$vmfld" "$ova"
  govc vm.markastemplate "$vmfld/rhcos-template"
fi
for vm in $(yq -r '.vms|keys[]' "$CLUSTER_FILE"); do
  ign="$baseDir/install-configs/$vm.ign"
  echo "Deploying $vm..."
  govc vm.clone -vm "$vmfld/rhcos-template" -on=false -folder "$vmfld" "$vm"
  govc vm.network.add -vm "$vm" -net "$vmnet" -net.adapter vmxnet3
  encoded=$(base64 -w0 <"$ign")
  govc vm.change -vm "$vm" -e "guestinfo.ignition.config.data.encoding=base64"
  govc vm.change -vm "$vm" -e "guestinfo.ignition.config.data=$encoded"
  govc vm.power -on "$vm"
done
EOS
chmod +x "$BASE/scripts/deploy-vms.sh"

# delete-cluster.sh
cat > "$BASE/scripts/delete-cluster.sh" <<'EOS'
#!/bin/zsh
set -e
CLUSTER_FILE=$1
if [ -z "$CLUSTER_FILE" ]; then echo "Usage: $0 <cluster.yaml>"; exit 1; fi
source "$(dirname "$0")/load-vcenter-env.sh"
baseDir="$(dirname "$(dirname "$0")")"
vmfld=$(yq '.vcenter_folder' "$CLUSTER_FILE")
echo "Confirm DELETE:"
read -p "> " c; [[ $c != DELETE ]] && exit 1
for vm in $(yq -r '.vms|keys[]' "$CLUSTER_FILE"); do
  path="$vmfld/$vm"
  if govc vm.info "$path" &>/dev/null; then
    govc vm.power -off -force "$path" || true
    govc vm.destroy "$path" || true
  fi
done
rm -rf "$baseDir/install-configs"
EOS
chmod +x "$BASE/scripts/delete-cluster.sh"

# vsphere-creds helper
cat > "$BASE/scripts/generate-vsphere-creds-manifest.sh" <<'EOS'
#!/bin/zsh
set -e
source "$(dirname "$0")/load-vcenter-env.sh"
baseDir="$(dirname "$(dirname "$0")")"
mkdir -p "$baseDir/install-configs/manifests"
u=$(echo -n "$GOVC_USERNAME" | base64)
p=$(echo -n "$GOVC_PASSWORD" | base64)
cat >"$baseDir/install-configs/manifests/vsphere-creds.yaml"<<YAML
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-creds
  namespace: openshift-machine-api
data:
  username: $u
  password: $p
YAML
EOS
chmod +x "$BASE/scripts/generate-vsphere-creds-manifest.sh"

# console-password helper
cat > "$BASE/scripts/generate-console-password-manifests.sh" <<'EOS'
#!/bin/zsh
set -e
CLUSTER_FILE=$1
pwf=$(yq '.consolePasswordFile' "$CLUSTER_FILE")
if [ -f "$pwf" ]; then
  h=$(<"$pwf")
  baseDir="$(dirname "$(dirname "$0")")"
  mkdir -p "$baseDir/install-configs/manifests"
  cat >"$baseDir/install-configs/manifests/99-user-pass.yaml"<<YAML
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-user-pass
spec:
  config:
    ignition:
      version: 3.2.0
    passwd:
      users:
        - name: core
          passwordHash: "$h"
YAML
fi
EOS
chmod +x "$BASE/scripts/generate-console-password-manifests.sh"

# rebuild-cluster.sh
cat > "$BASE/scripts/rebuild-cluster.sh" <<'EOS'
#!/bin/zsh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_FILE="$1"
if [ -z "$CLUSTER_FILE" ]; then echo "Usage: $0 <cluster.yaml>"; exit 1; fi
source "$SCRIPT_DIR/load-vcenter-env.sh"
export VSPHERE_USERNAME="$GOVC_USERNAME"
export VSPHERE_PASSWORD="$GOVC_PASSWORD"
$SCRIPT_DIR/delete-cluster.sh "$CLUSTER_FILE"
$SCRIPT_DIR/generate-install-config.sh "$CLUSTER_FILE"
cd "$(dirname "$SCRIPT_DIR")/install-configs"
export OPENSHIFT_INSTALL_EXPERIMENTAL_OVERRIDES='{ "disableTemplatedInstallConfig": true }'
openshift-install create manifests
cd "$SCRIPT_DIR"
$SCRIPT_DIR/generate-vsphere-creds-manifest.sh
$SCRIPT_DIR/generate-console-password-manifests.sh "$CLUSTER_FILE"
cd "$(dirname "$SCRIPT_DIR")/install-configs"
openshift-install create ignition-configs
cd "$SCRIPT_DIR"
$SCRIPT_DIR/deploy-vms.sh "$CLUSTER_FILE"
EOS
chmod +x "$BASE/scripts/rebuild-cluster.sh"

# bootstrap-cluster.sh
cat > "$BASE/scripts/bootstrap-cluster.sh" <<'EOS'
#!/bin/zsh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/load-vcenter-env.sh"
export VSPHERE_USERNAME="$GOVC_USERNAME"
export VSPHERE_PASSWORD="$GOVC_PASSWORD"
CLUSTER_FILE="$1"
if [ -z "$CLUSTER_FILE" ]; then echo "Usage: $0 <cluster.yaml>"; exit 1; fi
if [ ! -f "$CLUSTER_FILE" ]; then echo "❌ Not found: $CLUSTER_FILE"; exit 1; fi
REQUIRED=(assets/pull-secret.json assets/ssh-key.pub assets/rhcos-4.16.36-x86_64-vmware.x86_64.ova)
for f in "${REQUIRED[@]}"; do [ -f "$f" ] || { echo "Missing $f"; exit 1; }; done
$SCRIPT_DIR/deploy-cluster.sh "$CLUSTER_FILE"
EOS
chmod +x "$BASE/scripts/bootstrap-cluster.sh"

# Copy govc.env and assets
cp govc.env "$BASE/"
cp -r assets "$BASE/"

# Package into ZIP
zip -r "$ZIP" "$BASE"
echo "🔧 Built $ZIP"
