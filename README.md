# OpenShift vSphere Deployment Automation
Automated deployment scripts for installing Red Hat OpenShift on VMware vSphere with comprehensive static IP configuration, custom manifests, and robust cloud provider initialization handling.

_Last updated: 2025-06-15_

# Features
- ✅ **Automated vSphere VM deployment** using govc
- ✅ **Comprehensive static IP configuration** for all nodes
- ✅ **Individual ignition files** for each node
- ✅ **Custom manifest injection** (vSphere credentials, console authentication)
- ✅ **Shared RHCOS template** management or optional per-VM ISO
- ✅ **Dynamic network configuration** from cluster YAML
- ✅ **Cloud provider taint handling** to enable pod scheduling
- ✅ **vSphere credential validation** before deployment
- ✅ **Static IP verification** post-deployment

# Prerequisites
- [OpenShift installer](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/) (4.16.36+)
- [govc](https://github.com/vmware/govmomi/tree/master/govc)
- [yq](https://github.com/mikefarah/yq)
- [jq](https://stedolan.github.io/jq/)
- `mkisofs` (or install with `brew install cdrtools` on macOS)

# Getting Started
## 1. Setup Environment
```bash
cp govc.env.example govc.env
# Edit govc.env and set vSphere credentials (GOVC_URL, GOVC_USERNAME)
```

## 2. Prepare Assets
```bash
# Download RHCOS OVA or ISO
wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.16/rhcos-4.16.36-x86_64-live.x86_64.iso -O assets/rhcos-live.iso

# Add SSH key and pull secret
cp ~/.ssh/id_rsa.pub assets/ssh-key.pub
cp ~/.pull-secret assets/pull-secret.json

# Generate console password hash
python3 -c "import crypt; print(crypt.crypt('YourPassword', crypt.mksalt(crypt.METHOD_SHA512)))" > assets/console-password.txt
```

## 3. Define Cluster Configuration
```bash
cp clusters/ocp416.yaml.example clusters/ocp416.yaml
# Edit and specify cluster name, vCenter info, ISO path, network CIDR, gateway, etc.
```

## 4. Run Deployment
```bash
./scripts/rebuild-cluster.sh clusters/ocp416.yaml
```

# Configuration Notes
## Cluster YAML Example (clusters/ocp416.yaml)
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
network:
  cidr: 192.168.10.0/24
  gateway: 192.168.10.1
  dns_servers:
    - 192.168.10.1
```

# Scripts Overview
| Script | Purpose |
|--------|---------|
| `rebuild-cluster.sh` | Orchestrates full OpenShift cluster deployment |
| `deploy-vms.sh` / `deploy-vms-iso.sh` | Deploys VMs using template or ISO/ignition |
| `create-config-cdroms.sh` | Creates node-specific config ISO with ignition file |
| `upload-isos.sh` | Uploads generated ISOs to vSphere datastore |
| `generate-install-config.sh` | Generates OpenShift `install-config.yaml` |
| `generate-static-ip-manifests.sh` | Creates NetworkManager configs with static IPs |
| `create-individual-node-ignitions.sh` | Generates per-node ignition files |
| `generate-console-password-manifests.sh` | Injects web console login credentials |
| `fix-cloud-provider-taints.sh` | Handles cloud provider init delays |

# Notes on ISO Usage
- The ISO path is specified in the cluster YAML under `isoFile`
- All generated ignition configs are embedded as config ISOs per node
- The script automatically handles attaching CD-ROM drives to VMs and booting from ISO
- If using a VM template, ISO boot is optional — otherwise it's required

# Where to Get the ISO
Download from the [official OpenShift mirror](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.16/):
- Use `rhcos-4.16.36-x86_64-live.x86_64.iso` for ISO boot method
- Place it under `assets/` and reference in your cluster YAML as `isoFile: assets/rhcos-live.iso`

# Troubleshooting
- Ensure vSphere credentials are valid: `./scripts/validate-credentials.sh <cluster>`
- Confirm `govc` is configured correctly (env vars or `govc.env`)
- If VM boots from disk instead of ISO, check boot order and CD-ROM settings
- Use `govc vm.ip <vm-name>` to get IP address for debugging

# Final Notes
- Supports flexible YAML formats for networking (`network`, `subnet`, etc.)
- All ignition and static IP config files are verified post-deployment
- Log files and backups stored under `install-configs/<cluster>/`
