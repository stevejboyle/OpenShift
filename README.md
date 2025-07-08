# OpenShift UPI Automation for VMware vSphere

Automated deployment scripts for installing Red Hat OpenShift on VMware vSphere with comprehensive static IP configuration, custom manifests, and robust cloud provider initialization handling.

**Last updated: 2025-07-08**

## ✅ Features

- ✅ Automated vSphere VM deployment using govc
- ✅ Comprehensive static IP configuration for all nodes
- ✅ Individual ignition files for each node
- ✅ **NEW**: OVS bridge conflict resolution for OVN-Kubernetes
- ✅ **NEW**: NetworkManager configuration override for VM templates
- ✅ Custom manifest injection (vSphere credentials, console authentication)
- ✅ Shared RHCOS template management or optional per-VM ISO
- ✅ Dynamic network configuration from cluster YAML
- ✅ Cloud provider taint handling to enable pod scheduling
- ✅ vSphere credential validation before deployment
- ✅ Static IP verification post-deployment
- ✅ **NEW**: Enhanced bootstrap monitoring with timeout handling
- ✅ **NEW**: Cluster health verification and troubleshooting guidance

## 🚨 Important: OVS Bridge Conflict Resolution

**Common Issue**: If your RHCOS VM template contains legacy OVS bridge configuration (from OpenShift SDN era), it will conflict with OVN-Kubernetes and prevent proper network initialization.

**Symptoms**:
- Missing `ovn-k8s-gw0` interface on master nodes
- Ingress controller failing to start (`DeploymentUnavailable`)
- Authentication and console services unreachable
- Monitoring stack completely down

**Our Solution**: This automation now automatically detects and fixes OVS conflicts by:
1. Generating proper NetworkManager configurations for static IPs
2. Creating systemd services to remove OVS bridges on boot
3. Injecting network overrides into individual node ignition files
4. Ensuring OVN-Kubernetes can properly manage networking

## 📋 Prerequisites

### Required Tools
- [OpenShift installer](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/) (4.16.36+)
- [govc](https://github.com/vmware/govmomi/tree/master/govc)
- [yq](https://github.com/mikefarah/yq)
- [jq](https://stedolan.github.io/jq/) **NEW**: Required for network configuration merging
- `mkisofs` (or install with `brew install cdrtools` on macOS)

### Install Missing Tools
```bash
# On macOS
brew install jq yq

# On RHEL/CentOS
sudo yum install jq
pip3 install yq

# On Ubuntu/Debian  
sudo apt install jq
pip3 install yq
```

## 🚀 Quick Start

### 1. Setup Environment
```bash
# Copy and configure vSphere credentials
cp govc.env.example govc.env
# Edit govc.env and set vSphere credentials (GOVC_URL, GOVC_USERNAME)

# Download RHCOS ISO
wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.16/rhcos-4.16.36-x86_64-live.x86_64.iso -O assets/rhcos-live.iso

# Add SSH key and pull secret
cp ~/.ssh/id_rsa.pub assets/ssh-key.pub
cp ~/.pull-secret assets/pull-secret.json

# Generate console password hash
python3 -c "import crypt; print(crypt.crypt('YourPassword', crypt.mksalt(crypt.METHOD_SHA512)))" > assets/console-password.txt
```

### 2. Configure Your Cluster
```bash
# Copy example cluster configuration
cp clusters/ocp416.yaml.example clusters/ocp416.yaml
# Edit and specify cluster name, vCenter info, ISO path, network CIDR, gateway, etc.
```

### 3. Deploy Cluster
```bash
# Run the complete deployment automation
./scripts/rebuild-cluster.sh clusters/ocp416.yaml
```

The script will now automatically:
- Generate network configurations to override any OVS bridges in your VM template
- Create individual ignition files for each node with proper static IP configuration
- Deploy VMs with network-corrected ignition configs
- Monitor bootstrap and installation progress
- Apply necessary fixes for cloud provider taints
- Verify cluster health and provide access information

## 📁 Script Reference

| Script | Purpose | **Status** |
|--------|---------|------------|
| `rebuild-cluster.sh` | Orchestrates full OpenShift cluster deployment | **UPDATED** - Now includes OVS fix |
| `deploy-vms.sh` | Deploys VMs using template or ISO/ignition | Compatible |
| `deploy-vms-iso.sh` | Deploys VMs using ISO/ignition | Compatible |
| `generate-network-manifests.sh` | **NEW** - Creates NetworkManager configs to fix OVS conflicts | **NEW** |
| `merge-network-ignition.sh` | **NEW** - Merges network configs into individual ignition files | **NEW** |
| `create-config-cdroms.sh` | Creates node-specific config ISO with ignition file | Compatible |
| `upload-isos.sh` | Uploads generated ISOs to vSphere datastore | Compatible |
| `generate-install-config.sh` | Generates OpenShift install-config.yaml | Compatible |
| `create-individual-node-ignitions.sh` | Generates per-node ignition files | Compatible |
| `generate-console-password-manifests.sh` | Injects web console login credentials | Compatible |
| `fix-cloud-provider-taints.sh` | Handles cloud provider init delays | Compatible |

## ⚙️ Cluster Configuration

### Example cluster YAML:
```yaml
clusterName: ocp416
baseDomain: openshift.home.lab
vcenter_server: vcenter.lab.local
vcenter_datacenter: Datacenter
vcenter_cluster: Cluster
vcenter_datastore: datastore1
vcenter_network: VM Network

sshKeyFile: assets/ssh-key.pub
pullSecretFile: assets/pull-secret.json
consolePasswordFile: assets/console-password.txt
isoFile: assets/rhcos-live.iso

# **IMPORTANT**: Ensure your VM template path is correct
rhcos_vm_template: /Datacenter/vm/Templates/RHCOS-4.16-Template

network:
  cidr: 192.168.10.0/24
  gateway: 192.168.10.1
  dns_servers:
    - 192.168.10.1

node_counts:
  master: 3
  worker: 2

# **NEW**: Individual MAC addresses for static IP assignment
node_macs:
  bootstrap: "00:50:56:00:10:01"
  master-0: "00:50:56:00:10:02"
  master-1: "00:50:56:00:10:03"
  master-2: "00:50:56:00:10:04"
  worker-0: "00:50:56:00:10:11"
  worker-1: "00:50:56:00:10:12"
```

## 🔧 Network Configuration Details

### How OVS Conflict Resolution Works

1. **Detection**: The automation detects if your VM template has OVS bridge configuration
2. **Override Generation**: Creates proper NetworkManager configurations for each node
3. **Ignition Injection**: Merges network configs into individual ignition files
4. **Boot-time Fix**: Systemd service removes OVS bridges and applies correct config
5. **OVN-Kubernetes Compatibility**: Allows OVN to properly create `ovn-k8s-gw0` interfaces

### Generated Network Configuration

For each node, the automation creates:
```ini
[connection]
id=ens192
type=ethernet
interface-name=ens192

[ipv4]
method=manual
addresses=192.168.42.51/24
gateway=192.168.42.1
dns=192.168.1.97;192.168.1.98

[ipv6]
method=disabled
```

Plus a systemd service that removes any existing OVS bridges:
```bash
# Automatically removes: br-ex, ovs-if-br-ex, ovs-port-*, etc.
nmcli con delete br-ex ovs-if-br-ex ovs-port-br-ex ovs-port-phys0 ovs-if-phys0 || true
ovs-vsctl del-br br-ex || true
systemctl restart NetworkManager
```

## 🩺 Troubleshooting

### Common Issues and Solutions

#### 1. OVS Bridge Conflicts (RESOLVED)
**Symptoms**: Missing `ovn-k8s-gw0`, ingress controller down, authentication failing
**Solution**: ✅ **Automatically resolved** by the updated automation

#### 2. VM Template Issues
```bash
# Check if your template has OVS configuration
ssh core@master-0 'sudo nmcli con show'

# Good: Should show ethernet connections like 'ens192'
# Bad: Shows 'br-ex', 'ovs-if-br-ex', 'ovs-port-*'
```

#### 3. Network Verification
```bash
# Verify static IP configuration
oc get nodes -o wide

# Check OVN-Kubernetes pods
oc get pods -n openshift-ovn-kubernetes

# Verify gateway interfaces exist
ssh core@master-0 'ip addr show ovn-k8s-gw0'
```

#### 4. Cluster Operator Status
```bash
# Check operator health
oc get co

# Focus on critical operators
oc get co authentication ingress monitoring console

# Get detailed status
oc describe co ingress
```

### Manual Network Fix (If Automation Fails)

If the automatic OVS fix doesn't work, you can manually clean up:

```bash
# On each affected node:
ssh core@master-X

# Remove OVS connections
sudo nmcli con delete br-ex ovs-if-br-ex ovs-port-br-ex ovs-port-phys0 ovs-if-phys0

# Remove OVS bridge
sudo ovs-vsctl del-br br-ex

# Restart services
sudo systemctl restart NetworkManager
sudo systemctl restart kubelet
```

## 📚 Additional Information

### Bootstrap Process
The updated rebuild script provides enhanced monitoring:
- 60-minute timeout for bootstrap completion
- Real-time progress updates
- Automatic error detection and guidance

### Post-Installation Verification
After deployment, the script automatically:
- Checks cluster operator status
- Provides access credentials and URLs
- Offers troubleshooting commands
- Verifies network configuration

### ISO Boot Method
- The ISO path is specified in the cluster YAML under `isoFile`
- All generated ignition configs are embedded as config ISOs per node
- The script automatically handles attaching CD-ROM drives to VMs and booting from ISO
- If using a VM template, ISO boot is optional — otherwise it's required

### RHCOS Download
Download from the [official OpenShift mirror](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.16/):
- Use `rhcos-4.16.36-x86_64-live.x86_64.iso` for ISO boot method
- Place it under `assets/` and reference in your cluster YAML as `isoFile: assets/rhcos-live.iso`

## 🔒 Security Notes

- All ignition files contain embedded static IP configurations
- Network configurations are applied at first boot before any services start
- OVS bridge removal happens early in the boot process
- vSphere credentials are validated before deployment

## 📊 Monitoring and Logs

Log files and backups are stored under `install-configs/<cluster>/`:
- `install-config.yaml.bak` - Backup of install configuration
- `auth/` - Cluster authentication files
- `network-configs/` - **NEW** - Generated network configurations per node
- `*.ign.backup` - **NEW** - Backup of original ignition files before network merge

## 🆘 Support

If you encounter issues:

1. **Check the troubleshooting section above**
2. **Verify prerequisites are installed** (especially `jq`)
3. **Ensure VM template compatibility** with OVN-Kubernetes
4. **Review cluster operator status**: `oc get co`
5. **Check network interface status** on nodes

The automation now handles the most common UPI deployment issues automatically, but manual intervention may still be needed for environment-specific configurations.