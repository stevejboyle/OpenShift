# OpenShift vSphere Deployment Automation

Automated deployment scripts for installing Red Hat OpenShift on VMware vSphere with static IP configuration, custom manifests, and robust cloud provider initialization handling.

## Features

- ✅ **Automated vSphere VM deployment** using govc
- ✅ **Static IP configuration** for bootstrap and master nodes
- ✅ **Custom manifest injection** (vSphere credentials, console authentication, user passwords)
- ✅ **Shared RHCOS template** management
- ✅ **DNS configuration** from cluster YAML
- ✅ **Load balancer integration** (HAProxy)
- ✅ **Cloud provider taint handling** for reliable bootstrap
- ✅ **Backup and debugging** capabilities
- ✅ **End-to-end deployment monitoring** with status reporting
- 🆕 **Robust vSphere credential management** with format validation
- 🆕 **Automatic credential error prevention** and format checking

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
# Full automated deployment with cloud provider handling and credential validation
./scripts/rebuild-cluster.sh clusters/ocp416.yaml
```

The deployment script now includes:
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
network:
  cidr: 192.168.42.0/24
  gateway: 192.168.42.1
  dns_servers:
    - 192.168.1.97
    - 192.168.1.98
```

### Static IP Assignments
- **Bootstrap**: 192.168.42.30
- **Master-0**: 192.168.42.31
- **Master-1**: 192.168.42.32
- **Master-2**: 192.168.42.33
- **Workers**: DHCP (configurable)

### Load Balancer Configuration
Required DNS entries and load balancer backends:
- `api.ocp416.openshift.sboyle.internal` → 192.168.42.10 (HAProxy)
- `*.apps.ocp416.openshift.sboyle.internal` → 192.168.42.20 (HAProxy)

See [docs/haproxy-config.md](docs/haproxy-config.md) for complete HAProxy setup.

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `rebuild-cluster.sh` | **Main orchestration script** - full cluster rebuild with cloud provider handling |
| `fix-cloud-provider-taints.sh` | **NEW** - Detects and fixes cloud provider initialization issues |
| `validate-credentials.sh` | **🆕 NEW** - Validates vSphere credentials and secret format |
| `delete-cluster.sh` | Clean up VMs and generated configs |
| `deploy-cluster.sh` | **🆕 Enhanced** - Generate manifests with proper credential format |
| `deploy-vms.sh` | **🆕 Enhanced** - Deploy and configure VMs with credential validation |
| `generate-install-config.sh` | **🆕 Fixed** - Create install-config.yaml with real passwords (no placeholders) |
| `generate-static-ip-manifests.sh` | Create NetworkManager static IP configs |
| `generate-core-password-manifest.sh` | Set console access password for core user |
| `generate-vsphere-creds-manifest.sh` | **🆕 Fixed** - Inject vSphere credentials with standard format |
| `generate-console-password-manifests.sh` | Set up OpenShift console authentication |
| `inject-static-ips-into-ignition.sh` | Direct ignition file modification for static IPs |
| `load-vcenter-env.sh` | **🆕 Enhanced** - Load and validate vSphere environment variables |

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
3. **🆕 Credential Format Check**: Ensure no placeholders remain
4. **VM Deployment**: Deploy and configure VMs with static IPs
5. **Bootstrap Monitoring**: Wait for bootstrap completion (up to 40 minutes)
6. **Cloud Provider Handling**: Automatically detect and fix cloud provider initialization issues
7. **Critical Pod Verification**: Ensure etcd-operator and cloud-credential-operator are running
8. **Installation Completion**: Wait for full cluster installation
9. **🆕 Final Credential Validation**: Verify deployed credentials work correctly
10. **Status Reporting**: Show final cluster health and any issues

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

### Deploy New Cluster (Enhanced with Credential Validation)
```bash
# Full deployment with automatic credential validation and cloud provider handling
./scripts/rebuild-cluster.sh clusters/ocp416.yaml
```

The script will now show enhanced progress like:
```
🔍 Validating vSphere credentials...
✅ vSphere connectivity confirmed
📋 Loaded credentials for: administrator@vsphere.sboyle.internal @ vcenter1.sboyle.internal
🔐 Creating ALL required vSphere credentials secrets...
✅ Username format looks correct (contains @ and domain)
🚀 Deploying VMs...
🎉 VM deployment complete!
⏳ Waiting for cluster bootstrap to complete...
✅ Bootstrap completed successfully
🔧 Checking and fixing cloud provider initialization issues...
🔍 Validating deployed credentials...
✅ All credential validations passed
🏁 Final cluster status:
✅ Cluster API is accessible
✅ All cluster operators healthy
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
- **🆕 Credential validation** at multiple stages
- Bootstrap completion detection
- Cloud provider issue detection and fixing
- Critical pod readiness verification
- Installation completion monitoring
- **🆕 Final credential verification**
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
ssh core@192.168.42.30

# vCenter console with password
# Username: core
# Password: [your-password]
```

## Troubleshooting

### 🆕 Automatic Credential Issue Resolution

The deployment scripts now automatically handle:
- **🆕 Credential format validation** - ensures standard format used
- **🆕 Placeholder password removal** - prevents authentication failures
- **🆕 vSphere connectivity testing** - validates credentials before deployment
- **🆕 Machine API authentication** - verifies credentials work in deployed cluster
- **Cloud provider initialization delays** - automatically removes blocking taints
- **Pod scheduling failures** - verifies critical pods can start
- **Bootstrap timeouts** - continues with installation after fixing issues

### Common Issues

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

**Bootstrap timeout:**
- The script now handles this automatically by proceeding to cloud provider checks
- Check HAProxy configuration for port 22623
- Verify masters can reach bootstrap: `curl -k https://192.168.42.30:22623/config/master`

### 🆕 Enhanced Debug Commands
```bash
# Validate credentials in deployed cluster
./scripts/validate-credentials.sh ocp416

# Check credential format in secrets
oc get secret vsphere-cloud-credentials -n openshift-machine-api -o yaml

# Check for authentication errors in machines
oc describe machines -n openshift-machine-api | grep -A5 -B5 "Cannot complete login"

# Check VM IPs
govc vm.ip ocp416-bootstrap
govc vm.ip ocp416-master-0

# Check cluster status
oc get nodes
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
```

### Script Debugging

The enhanced scripts provide detailed logging:
```bash
# Check recent deployment logs
tail -f /tmp/openshift-install-*.log

# Check cloud provider fix logs
./scripts/fix-cloud-provider-taints.sh install-configs/ocp416

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
│   └── ocp416.yaml
├── scripts/
│   ├── rebuild-cluster.sh          # Enhanced with credential validation
│   ├── fix-cloud-provider-taints.sh # Cloud provider issue resolution
│   ├── validate-credentials.sh     # 🆕 NEW - Credential validation
│   ├── delete-cluster.sh
│   ├── deploy-cluster.sh           # 🆕 Enhanced credential generation
│   ├── deploy-vms.sh               # 🆕 Enhanced with validation
│   ├── generate-install-config.sh  # 🆕 Fixed placeholder password issue
│   ├── load-vcenter-env.sh         # 🆕 Enhanced validation
│   └── [other scripts...]
├── install-configs/
│   └── ocp416/
│       ├── *.ign
│       ├── auth/
│       └── manifests-backup-*/
├── govc.env
└── README.md
```

## What's New in v3.0

### 🆕 Robust Credential Management
- **Automatic credential format validation**
- **Real password embedding** (no more placeholders)
- **Standard secret format enforcement**
- **Pre-deployment vSphere connectivity testing**
- **Post-deployment credential verification**

### 🆕 Enhanced Error Prevention
- **Authentication cascade failure prevention**
- **Machine API credential format validation**
- **Comprehensive secret generation for all components**
- **Format mismatch detection and correction**

### 🆕 Improved Troubleshooting
- **New credential validation script**
- **Enhanced error messages and debugging**
- **Automatic credential issue detection**
- **Clear remediation steps for credential problems**

### Enhanced Deployment Reliability
- **Automatic cloud provider taint detection and removal**
- **Critical pod readiness verification**
- **End-to-end installation monitoring**
- **Comprehensive error handling and recovery**

### Better User Experience
- **Real-time progress reporting with emojis**
- **Automatic issue detection and resolution**
- **Clear status reporting at each stage**
- **Detailed final cluster health summary**

## Security Notes

- Never commit sensitive files (credentials, pull secrets, private keys)
- Use `.gitignore` to exclude sensitive assets
- Set `GOVC_PASSWORD` as environment variable or script will prompt securely
- Rotate passwords and certificates regularly
- Follow Red Hat and VMware security best practices

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly with various vSphere environments
4. Submit a pull request with detailed description
5. Include any updates to credential handling logic

## License

Use it or don't use it. You don't need to pay me but don't complain either

## Support

- [Red Hat OpenShift Documentation](https://docs.openshift.com/)
- [VMware vSphere Documentation](https://docs.vmware.com/en/VMware-vSphere/)
- [OpenShift on vSphere Guide](https://docs.openshift.com/container-platform/4.16/installing/installing_vsphere/)
- **🆕 Enhanced troubleshooting**: Check credential validation with `validate-credentials.sh`
- **Enhanced troubleshooting**: Check the automatic cloud provider handling in `fix-cloud-provider-taints.sh`