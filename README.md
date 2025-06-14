# OpenShift vSphere Deployment Automation

Automated deployment scripts for installing Red Hat OpenShift on VMware vSphere with comprehensive static IP configuration, custom manifests, and robust cloud provider initialization handling.

## Features

- ✅ **Automated vSphere VM deployment** using govc
- ✅ **🆕 Comprehensive static IP configuration** for all nodes (bootstrap, masters, workers)
- ✅ **🆕 Individual ignition files** for each node with specific static IPs
- ✅ **Custom manifest injection** (vSphere credentials, console authentication, user passwords)
- ✅ **Shared RHCOS template** management
- ✅ **Dynamic network configuration** from cluster YAML
- ✅ **Load balancer integration** (HAProxy)
- ✅ **Cloud provider taint handling** for reliable bootstrap
- ✅ **Backup and debugging** capabilities
- ✅ **End-to-end deployment monitoring** with status reporting
- 🆕 **Robust vSphere credential management** with format validation
- 🆕 **Automatic credential error prevention** and format checking
- 🆕 **Per-node static IP assignment** via individual ignition files

## Prerequisites

### Software Requirements
- [OpenShift installer](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/) (4.16.36+)
- [govc](https://github.com/vmware/govmomi/tree/master/govc) (VMware vSphere CLI)
- [yq](https://github.com/mikefarah/yq) (YAML processor)
- [jq](https://stedolan.github.io/jq/) (JSON processor)

### Infrastructure Requirements
- VMware vSphere environment (vCenter + ESXi)
- Load balancer (HAProxy recommended)
- DNS server with required entries
- RHCOS OVA template

## Quick Start

### 1. Clone and Setup
```bash
git clone <your-repo>
cd openshift-vsphere-automation
chmod +x scripts/*.sh
```

### 2. Configure Environment
```bash
# Copy and edit the govc environment file
cp govc.env.example govc.env
# Edit govc.env with your vSphere credentials
# Set GOVC_USERNAME (e.g., administrator@vsphere.sboyle.internal)
# Set GOVC_PASSWORD in environment or script will prompt
```

### 3. Prepare Assets
```bash
# Download RHCOS OVA
wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.16/rhcos-4.16.36-x86_64-vmware.x86_64.ova -O assets/

# Add your SSH public key
cp ~/.ssh/id_rsa.pub assets/ssh-key.pub

# Add your Red Hat pull secret
# Get from: https://console.redhat.com/openshift/install/pull-secret
cat > assets/pull-secret.json <<EOF
{"auths":{"your-pull-secret-here"}}
EOF

# Generate console password hash
python3 -c "import crypt; print(crypt.crypt('YourPassword', crypt.mksalt(crypt.METHOD_SHA512)))" > assets/console-password.txt
```

### 4. Configure Cluster
```bash
# Edit your cluster configuration
cp clusters/ocp416.yaml.example clusters/ocp416.yaml
# Customize cluster settings, network, DNS, etc.
```

### 5. Deploy
```bash
# Full automated deployment with static IPs and credential validation
./scripts/rebuild-cluster.sh clusters/ocp416.yaml
```

The deployment script now includes:
- **🆕 Dynamic network configuration** - reads network settings from cluster YAML
- **🆕 Individual node ignition files** - each VM gets specific static IP configuration
- **Automatic bootstrap monitoring** - waits for bootstrap completion
- **🆕 vSphere credential validation** - ensures credentials work before deployment
- **🆕 Credential format verification** - prevents authentication cascade failures
- **Cloud provider taint detection and removal** - prevents scheduling failures
- **Critical pod verification** - ensures etcd and cloud operators start properly
- **Installation completion monitoring** - waits for full cluster readiness
- **Comprehensive status reporting** - shows final cluster health

## Configuration

### Cluster Configuration (clusters/ocp416.yaml)
```yaml
clusterName: ocp416
baseDomain: openshift.sboyle.internal
vcenter_server: vcenter1.sboyle.internal
vcenter_username: administrator@vsphere.sboyle.internal
vcenter_datacenter: Lab
vcenter_cluster: Lab Cluster
vcenter_datastore: datastore-SAN1
vcenter_network: OpenShift_192.168.42.0
sshKeyFile: assets/ssh-key.pub
pullSecretFile: assets/pull-secret.json
consolePasswordFile: assets/console-password.txt
# 🆕 Dynamic network configuration
network:
  cidr: 192.168.42.0/24
  gateway: 192.168.42.1
  dns_servers:
    - 192.168.1.97
    - 192.168.1.98
```

### 🆕 Static IP Assignments (Automatic)
The deployment now automatically assigns static IPs based on your network configuration:

- **Bootstrap**: `{network_base}.30` (e.g., 192.168.42.30)
- **Master-0**: `{network_base}.31` (e.g., 192.168.42.31)
- **Master-1**: `{network_base}.32` (e.g., 192.168.42.32)
- **Master-2**: `{network_base}.33` (e.g., 192.168.42.33)
- **Worker-0**: `{network_base}.40` (e.g., 192.168.42.40)
- **Worker-1**: `{network_base}.41` (e.g., 192.168.42.41)

Where `{network_base}` is automatically extracted from your `network.cidr` configuration.

### Load Balancer Configuration
Required DNS entries and load balancer backends:
- `api.ocp416.openshift.sboyle.internal` → 192.168.42.10 (HAProxy)
- `*.apps.ocp416.openshift.sboyle.internal` → 192.168.42.20 (HAProxy)

**🆕 Load Balancer Backend Configuration:**
```
# API Backend (port 6443)
server bootstrap 192.168.42.30:6443 check
server master-0 192.168.42.31:6443 check
server master-1 192.168.42.32:6443 check
server master-2 192.168.42.33:6443 check

# Apps Backend (ports 80/443)
server worker-0 192.168.42.40:80 check
server worker-1 192.168.42.41:80 check
```

See [docs/haproxy-config.md](docs/haproxy-config.md) for complete HAProxy setup.

## 🆕 Static IP Implementation

### How Static IPs Work
The deployment uses a multi-layered approach for reliable static IP assignment:

1. **Bootstrap Node**: Uses machine config manifest that gets embedded in bootstrap.ign
2. **Master Nodes**: Individual ignition files (master-0.ign, master-1.ign, master-2.ign) with specific IPs
3. **Worker Nodes**: Individual ignition files (worker-0.ign, worker-1.ign) with specific IPs

### 🆕 Individual Ignition Files
Each VM gets its own ignition file with embedded static IP configuration:

```bash
install-configs/ocp416/
├── bootstrap.ign      # Contains static IP for .30
├── master-0.ign       # Contains static IP for .31
├── master-1.ign       # Contains static IP for .32
├── master-2.ign       # Contains static IP for .33
├── worker-0.ign       # Contains static IP for .40
├── worker-1.ign       # Contains static IP for .41
└── worker.ign         # Original (unused)
```

### 🆕 NetworkManager Configuration
Each ignition file contains a NetworkManager connection profile:

```ini
[connection]
id=ens192
type=ethernet
interface-name=ens192
autoconnect=true
autoconnect-priority=999

[ethernet]

[ipv4]
address1=192.168.42.31/24,192.168.42.1
dns=192.168.1.97;
method=manual

[ipv6]
addr-gen-mode=eui64
method=disabled
```

### 🆕 Dynamic Network Parsing
The scripts automatically read network configuration from your cluster YAML:

```yaml
# Supported formats:
network:
  cidr: 192.168.42.0/24
  gateway: 192.168.42.1
  dns_servers:
    - 192.168.1.97
    - 192.168.1.98

# Or simplified format:
network: 192.168.42.0/24

# Or alternative naming:
subnet:
  cidr: 10.0.100.0/24
  gateway: 10.0.100.1
```

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `rebuild-cluster.sh` | **Main orchestration script** - full cluster rebuild with static IPs and cloud provider handling |
| `generate-static-ip-manifests.sh` | **🆕 Enhanced** - Create NetworkManager static IP configs with dynamic network parsing |
| `create-individual-node-ignitions.sh` | **🆕 NEW** - Generate individual ignition files for each node with specific static IPs |
| `deploy-vms.sh` | **🆕 Enhanced** - Deploy VMs using individual ignition files |
| `fix-cloud-provider-taints.sh` | **NEW** - Detects and fixes cloud provider initialization issues |
| `validate-credentials.sh` | **🆕 NEW** - Validates vSphere credentials and secret format |
| `delete-cluster.sh` | Clean up VMs and generated configs |
| `deploy-cluster.sh` | **🆕 Enhanced** - Generate manifests with proper credential format |
| `generate-install-config.sh` | **🆕 Fixed** - Create install-config.yaml with real passwords (no placeholders) |
| `generate-core-password-manifest.sh` | Set console access password for core user |
| `generate-vsphere-creds-manifest.sh` | **🆕 Fixed** - Inject vSphere credentials with standard format |
| `generate-console-password-manifests.sh` | Set up OpenShift console authentication |
| `inject-static-ips-into-ignition.sh` | Direct ignition file modification for static IPs |
| `load-vcenter-env.sh` | **🆕 Enhanced** - Load and validate vSphere environment variables |

## 🆕 Enhanced Static IP Management

### Automatic Network Configuration
The deployment scripts now automatically:
- **Parse network settings** from cluster YAML configuration
- **Extract network base** from CIDR notation (e.g., 192.168.42.0/24 → 192.168.42)
- **Use provided gateway** or default to `.1`
- **Use provided DNS servers** or fall back to gateway
- **Generate sequential IP assignments** based on node type and index

### Individual Node Configurations
Each node gets a tailored configuration:

```bash
# Bootstrap node - via machine config in bootstrap.ign
Bootstrap: {network_base}.30

# Master nodes - via individual ignition files
Master-0:  {network_base}.31  (master-0.ign)
Master-1:  {network_base}.32  (master-1.ign)
Master-2:  {network_base}.33  (master-2.ign)

# Worker nodes - via individual ignition files
Worker-0:  {network_base}.40  (worker-0.ign)
Worker-1:  {network_base}.41  (worker-1.ign)
```

### 🆕 Deployment Integration
The `deploy-vms.sh` script automatically detects and uses the correct ignition file:

```bash
# VM naming to ignition file mapping:
ocp416-bootstrap → bootstrap.ign
ocp416-master-0  → master-0.ign
ocp416-master-1  → master-1.ign
ocp416-master-2  → master-2.ign
ocp416-worker-0  → worker-0.ign
ocp416-worker-1  → worker-1.ign
```

## 🆕 Credential Management Enhancements

### What Was Fixed
The deployment automation now includes robust credential handling that prevents the most common vSphere authentication failures:

**Previous Issues:**
- ❌ Placeholder passwords (`WILL_BE_SET_BY_ENVIRONMENT`) remained in secrets
- ❌ Server-specific credential keys (`vcenter.domain.com.username`) instead of standard format
- ❌ Missing credential validation before deployment
- ❌ Authentication cascade failures affecting entire cluster

**New Solutions:**
- ✅ **Real passwords embedded** in install-config.yaml and manifests
- ✅ **Standard credential format** (`username`/`password` keys) used consistently
- ✅ **Pre-deployment credential validation** ensures vSphere connectivity
- ✅ **Format verification** prevents authentication failures
- ✅ **Comprehensive secret generation** for all required components

### Credential Validation
```bash
# Validate credentials before deployment
./scripts/validate-credentials.sh ocp416

# Validate deployed cluster credentials
export KUBECONFIG=install-configs/ocp416/auth/kubeconfig
./scripts/validate-credentials.sh ocp416
```

### Credential Format
The scripts now ensure all vSphere secrets use the **standard format**:
```yaml
data:
  username: <base64-encoded-username>
  password: <base64-encoded-password>
```

**Not the problematic server-specific format:**
```yaml
data:
  vcenter1.sboyle.internal.username: <base64>
  vcenter1.sboyle.internal.password: <base64>
```

## Deployment Flow

The enhanced `rebuild-cluster.sh` now follows this robust deployment flow:

1. **🆕 Credential Validation**: Verify vSphere credentials and format
2. **Pre-deployment**: Clean up, generate configs, inject manifests
3. **🆕 Static IP Manifest Generation**: Create NetworkManager configs with dynamic network parsing
4. **🆕 Credential Format Check**: Ensure no placeholders remain
5. **Ignition Generation**: Create base ignition files
6. **🆕 Individual Node Ignition Creation**: Generate specific ignition files for each node with static IPs
7. **VM Deployment**: Deploy and configure VMs with individual ignition files
8. **Bootstrap Monitoring**: Wait for bootstrap completion (up to 40 minutes)
9. **Cloud Provider Handling**: Automatically detect and fix cloud provider initialization issues
10. **Critical Pod Verification**: Ensure etcd-operator and cloud-credential-operator are running
11. **Installation Completion**: Wait for full cluster installation
12. **🆕 Final Credential Validation**: Verify deployed credentials work correctly
13. **🆕 Static IP Verification**: Confirm all nodes have their assigned static IPs
14. **Status Reporting**: Show final cluster health and any issues

### 🆕 Static IP Verification

The deployment process now includes automatic verification:

```bash
# Automatically checks that each VM has its expected IP
✅ Static IP verification:
   Bootstrap (192.168.42.30): ✅ Configured
   Master-0 (192.168.42.31):  ✅ Configured  
   Master-1 (192.168.42.32):  ✅ Configured
   Master-2 (192.168.42.33):  ✅ Configured
   Worker-0 (192.168.42.40):  ✅ Configured
   Worker-1 (192.168.42.41):  ✅ Configured
```

### 🆕 Credential Error Prevention

The new credential handling automatically:
- **Validates username format** (should be user@domain.tld)
- **Tests vSphere connectivity** before VM deployment
- **Removes placeholder passwords** from all manifests
- **Uses consistent secret format** across all components
- **Verifies credential secrets** in deployed cluster

This prevents the common authentication cascade where:
```
Machine API can't authenticate → Control plane machines fail → 
Authentication operator fails → Console fails → Ingress fails
```

### Cloud Provider Taint Handling

The `fix-cloud-provider-taints.sh` script automatically:
- Detects `node.cloudprovider.kubernetes.io/uninitialized` taints that prevent pod scheduling
- Removes these taints when cloud provider initialization is delayed
- Verifies critical system pods can schedule and start
- Provides detailed logging for troubleshooting

## Usage Examples

### Deploy New Cluster (Enhanced with Static IP and Credential Validation)
```bash
# Full deployment with automatic static IP assignment and credential validation
./scripts/rebuild-cluster.sh clusters/ocp416.yaml
```

The script will now show enhanced progress like:
```
🔍 Validating vSphere credentials...
✅ vSphere connectivity confirmed
📡 Using network: 192.168.42.0/24
🏠 Network base: 192.168.42
🚪 Gateway: 192.168.42.1
🌐 DNS: 192.168.1.97
🌐 Generating static IP manifests for cluster ocp416...
✅ Static IP manifests generated:
   Bootstrap: 192.168.42.30
   Master-0:  192.168.42.31
   Master-1:  192.168.42.32
   Master-2:  192.168.42.33
   Worker-0:  192.168.42.40
   Worker-1:  192.168.42.41
🔧 Creating individual master and worker ignition files with static IPs...
✅ Individual ignition files created
📋 Loaded credentials for: administrator@vsphere.sboyle.internal @ vcenter1.sboyle.internal
🔐 Creating ALL required vSphere credentials secrets...
✅ Username format looks correct (contains @ and domain)
🚀 Deploying VMs...
✅ Applied ignition config: master-0.ign
✅ Applied ignition config: master-1.ign
✅ Applied ignition config: master-2.ign
✅ Applied ignition config: worker-0.ign
✅ Applied ignition config: worker-1.ign
🎉 VM deployment complete!
⏳ Waiting for cluster bootstrap to complete...
✅ Bootstrap completed successfully
🔧 Checking and fixing cloud provider initialization issues...
🔍 Validating deployed credentials...
✅ All credential validations passed
✅ Static IP verification completed
🏁 Final cluster status:
✅ Cluster API is accessible
✅ All cluster operators healthy
```

### 🆕 Generate Static IP Configurations Only
```bash
# Generate static IP manifests without full deployment
./scripts/generate-static-ip-manifests.sh clusters/ocp416.yaml

# Generate individual ignition files with static IPs
./scripts/create-individual-node-ignitions.sh clusters/ocp416.yaml
```

### 🆕 Validate Credentials (New Feature)
```bash
# Validate credentials before deployment
./scripts/validate-credentials.sh ocp416

# Validate deployed cluster credentials
export KUBECONFIG=install-configs/ocp416/auth/kubeconfig
./scripts/validate-credentials.sh ocp416
```

### 🆕 Fix Credential Issues (Manual)
```bash
# If you encounter credential format issues in existing cluster
oc delete secret vsphere-cloud-credentials -n openshift-machine-api
oc create secret generic vsphere-cloud-credentials \
  --from-literal=username="administrator@vsphere.sboyle.internal" \
  --from-literal=password="your-password" \
  -n openshift-machine-api
oc delete pods -n openshift-machine-api -l k8s-app=machine-api-controllers
```

### Fix Cloud Provider Issues (Manual)
```bash
# If you need to manually fix cloud provider issues on existing cluster
./scripts/fix-cloud-provider-taints.sh install-configs/ocp416
```

### Delete Cluster (with confirmation)
```bash
./scripts/delete-cluster.sh clusters/ocp416.yaml
```

## Monitoring Installation

### Automated Monitoring (Built-in)
The `rebuild-cluster.sh` script now includes comprehensive monitoring:
- **🆕 Network configuration parsing and validation**
- **🆕 Static IP assignment verification**
- **🆕 Individual ignition file creation and validation**
- **🆕 Credential validation** at multiple stages
- Bootstrap completion detection
- Cloud provider issue detection and fixing
- Critical pod readiness verification
- Installation completion monitoring
- **🆕 Final credential verification**
- **🆕 Final static IP verification**
- Final cluster status reporting

### Manual Monitoring
```bash
cd install-configs/ocp416

# Watch bootstrap progress
openshift-install wait-for bootstrap-complete --log-level debug

# Watch installation completion
openshift-install wait-for install-complete --log-level debug

# Check cluster status
export KUBECONFIG=auth/kubeconfig
oc get nodes
oc get co  # Check cluster operators
oc get pods --all-namespaces | grep -v Running

# 🆕 Check node IP assignments
oc get nodes -o wide

# 🆕 Verify static IP configurations
for vm in bootstrap master-0 master-1 master-2 worker-0 worker-1; do
  echo "Checking ${vm}..."
  govc vm.ip ocp416-${vm}
done

# 🆕 Check machine authentication status
oc describe machines -n openshift-machine-api | grep -A5 -B5 "Cannot complete login"
```

## Console Access

### Web Console
- **URL**: `https://console-openshift-console.apps.ocp416.openshift.sboyle.internal`
- **Admin User**: `admin` / `[your-password]`
- **Kubeadmin**: `kubeadmin` / `[generated-password]`

### CLI Access
```bash
export KUBECONFIG=install-configs/ocp416/auth/kubeconfig
oc login -u admin
```

### Node Console Access
```bash
# SSH with key
ssh core@192.168.42.30  # Bootstrap
ssh core@192.168.42.31  # Master-0
ssh core@192.168.42.32  # Master-1
ssh core@192.168.42.33  # Master-2
ssh core@192.168.42.40  # Worker-0
ssh core@192.168.42.41  # Worker-1

# vCenter console with password
# Username: core
# Password: [your-password]
```

## Troubleshooting

### 🆕 Automatic Static IP Issue Resolution

The deployment scripts now automatically handle:
- **🆕 Dynamic network configuration parsing** - reads from cluster YAML
- **🆕 Individual ignition file generation** - ensures each node gets specific IP
- **🆕 NetworkManager configuration validation** - verifies network configs are correct
- **🆕 IP assignment verification** - confirms VMs get their expected IPs
- **🆕 Credential format validation** - ensures standard format used
- **🆕 Placeholder password removal** - prevents authentication failures
- **🆕 vSphere connectivity testing** - validates credentials before deployment
- **🆕 Machine API authentication** - verifies credentials work in deployed cluster
- **Cloud provider initialization delays** - automatically removes blocking taints
- **Pod scheduling failures** - verifies critical pods can start
- **Bootstrap timeouts** - continues with installation after fixing issues

### Common Issues

**🆕 Static IP Assignment Issues (Automatically Prevented):**
- **Symptoms**: VMs not getting expected static IPs
- **Automatic Prevention**: Individual ignition files ensure each VM gets specific IP
- **Manual Check**: `govc vm.ip ocp416-master-0` should show 192.168.42.31
- **Manual Fix**: Check NetworkManager logs: `sudo journalctl -u NetworkManager`
- **Root Cause**: Usually network configuration or DNS issues

**🆕 Network Configuration Issues (Automatically Detected):**
- **Symptoms**: Script fails to parse network from cluster YAML
- **Automatic Detection**: Script validates network configuration before proceeding
- **Manual Fix**: Ensure cluster YAML has valid `network.cidr` or `subnet.cidr`
- **Example**: `network: { cidr: "192.168.42.0/24", gateway: "192.168.42.1" }`

**🆕 Individual Ignition File Issues (Automatically Fixed):**
- **Symptoms**: VMs boot but don't get static IPs
- **Automatic Fix**: Script validates ignition files contain NetworkManager configs
- **Manual Check**: `jq '.storage.files[] | select(.path | contains("system-connections"))' master-0.ign`
- **Manual Fix**: Re-run `./scripts/create-individual-node-ignitions.sh clusters/ocp416.yaml`

**🆕 vSphere Authentication Failures (Automatically Prevented):**
- **Symptoms**: Machine API cannot connect to vSphere, authentication errors
- **Automatic Prevention**: Scripts validate credentials and format before deployment
- **Manual Fix**: Run `./scripts/validate-credentials.sh` to diagnose and fix
- **Root Cause**: Usually placeholder passwords or server-specific credential keys

**🆕 Credential Format Issues (Automatically Fixed):**
- **Symptoms**: Secrets exist but Machine API can't read them
- **Automatic Fix**: Scripts generate all secrets with standard format
- **Manual Check**: `oc get secret vsphere-cloud-credentials -n openshift-machine-api -o yaml`
- **Should see**: `username:` and `password:` keys, not server-specific keys

**Cloud Provider Initialization Issues (Automatically Fixed):**
- **Symptoms**: Pods stuck in "Pending" with `node.cloudprovider.kubernetes.io/uninitialized` taints
- **Automatic Fix**: The script detects and removes these taints
- **Manual Fix**: Run `./scripts/fix-cloud-provider-taints.sh install-configs/ocp416`

**VMs not getting static IPs:**
- Check manifest backup in `install-configs/ocp416/manifests-backup-*/`
- Verify DNS servers are reachable
- Check NetworkManager logs: `sudo journalctl -u NetworkManager`
- Verify individual ignition files exist: `ls install-configs/ocp416/master-*.ign worker-*.ign`

**Bootstrap timeout:**
- The script now handles this automatically by proceeding to cloud provider checks
- Check HAProxy configuration for port 22623
- Verify masters can reach bootstrap: `curl -k https://192.168.42.30:22623/config/master`

### 🆕 Enhanced Debug Commands
```bash
# Validate network configuration parsing
./scripts/generate-static-ip-manifests.sh clusters/ocp416.yaml

# Check individual ignition files
ls -la install-configs/ocp416/*.ign
jq '.storage.files[] | select(.path | contains("system-connections")) | .path' install-configs/ocp416/master-0.ign

# Validate credentials in deployed cluster
./scripts/validate-credentials.sh ocp416

# Check credential format in secrets
oc get secret vsphere-cloud-credentials -n openshift-machine-api -o yaml

# Check for authentication errors in machines
oc describe machines -n openshift-machine-api | grep -A5 -B5 "Cannot complete login"

# Check VM IPs match expected assignments
echo "Expected vs Actual IP assignments:"
echo "Bootstrap (expected 192.168.42.30): $(govc vm.ip ocp416-bootstrap)"
echo "Master-0 (expected 192.168.42.31):  $(govc vm.ip ocp416-master-0)"
echo "Master-1 (expected 192.168.42.32):  $(govc vm.ip ocp416-master-1)"
echo "Master-2 (expected 192.168.42.33):  $(govc vm.ip ocp416-master-2)"
echo "Worker-0 (expected 192.168.42.40):  $(govc vm.ip ocp416-worker-0)"
echo "Worker-1 (expected 192.168.42.41):  $(govc vm.ip ocp416-worker-1)"

# Check cluster status
oc get nodes -o wide
oc get csr
oc get co

# Check for taint issues
oc get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# Check critical pods
oc get pods -n openshift-etcd-operator
oc get pods -n openshift-cloud-credential-operator
oc get pods -n openshift-machine-api

# Test vSphere connectivity
source scripts/load-vcenter-env.sh
govc about

# 🆕 Verify NetworkManager configurations on nodes
ssh core@192.168.42.31 "sudo cat /etc/NetworkManager/system-connections/ens192.nmconnection"
```

### Script Debugging

The enhanced scripts provide detailed logging:
```bash
# Check recent deployment logs
tail -f /tmp/openshift-install-*.log

# Check cloud provider fix logs
./scripts/fix-cloud-provider-taints.sh install-configs/ocp416

# 🆕 Check static IP generation logs
./scripts/generate-static-ip-manifests.sh clusters/ocp416.yaml

# 🆕 Check individual ignition creation logs
./scripts/create-individual-node-ignitions.sh clusters/ocp416.yaml

# 🆕 Check credential validation logs
./scripts/validate-credentials.sh ocp416
```

## File Structure
```
.
├── assets/
│   ├── ssh-key.pub
│   ├── pull-secret.json
│   ├── console-password.txt
│   └── rhcos-4.16.36-x86_64-vmware.x86_64.ova
├── clusters/
│   └── ocp416.yaml                      # 🆕 Enhanced with network config
├── scripts/
│   ├── rebuild-cluster.sh               # Enhanced with static IP orchestration
│   ├── generate-static-ip-manifests.sh  # 🆕 Enhanced with dynamic network parsing
│   ├── create-individual-node-ignitions.sh # 🆕 NEW - Individual ignition files
│   ├── deploy-vms.sh                    # 🆕 Enhanced to use individual ignitions
│   ├── fix-cloud-provider-taints.sh     # Cloud provider issue resolution
│   ├── validate-credentials.sh          # 🆕 NEW - Credential validation
│   ├── delete-cluster.sh
│   ├── deploy-cluster.sh                # 🆕 Enhanced credential generation
│   ├── generate-install-config.sh       # 🆕 Fixed placeholder password issue
│   ├── load-vcenter-env.sh              # 🆕 Enhanced validation
│   └── [other scripts...]
├── install-configs/
│   └── ocp416/
│       ├── bootstrap.ign               # Contains static IP for bootstrap
│       ├── master-0.ign                # 🆕 Individual master ignitions
│       ├── master-1.ign                # 🆕 with specific static IPs
│       ├── master-2.ign                # 🆕
│       ├── worker-0.ign                # 🆕 Individual worker ignitions  
│       ├── worker-1.ign                # 🆕 with specific static IPs
│       ├── master.ign                  # Original (base template)
│       ├── worker.ign                  # Original (base template)
│       ├── auth/
│       └── manifests-backup-*/
├── govc.env
└── README.md
```

## What's New in v4.0

### 🆕 Comprehensive Static IP Management
- **Dynamic network configuration parsing** from cluster YAML
- **Individual ignition files** for each node with specific static IPs
- **Automatic IP assignment** based on node type and network configuration
- **NetworkManager integration** for reliable static IP configuration
- **Per-node IP verification** during deployment

### 🆕 Enhanced Network Configuration
- **Flexible YAML