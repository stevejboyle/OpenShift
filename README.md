# OpenShift vSphere Deployment Automation

Automated deployment scripts for installing Red Hat OpenShift on VMware vSphere with static IP configuration and custom manifests.

## Features

- ✅ **Automated vSphere VM deployment** using govc
- ✅ **Static IP configuration** for bootstrap and master nodes
- ✅ **Custom manifest injection** (vSphere credentials, console authentication, user passwords)
- ✅ **Shared RHCOS template** management
- ✅ **DNS configuration** from cluster YAML
- ✅ **Load balancer integration** (HAProxy)
- ✅ **Backup and debugging** capabilities

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
# Edit govc.env with your vSphere credentials (without password)
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
# Full automated deployment
./scripts/rebuild-cluster.sh clusters/ocp416.yaml
```

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
| `rebuild-cluster.sh` | Main orchestration script - full cluster rebuild |
| `delete-cluster.sh` | Clean up VMs and generated configs |
| `deploy-cluster.sh` | Generate manifests and ignition configs |
| `deploy-vms.sh` | Deploy and configure VMs |
| `generate-install-config.sh` | Create OpenShift install-config.yaml |
| `generate-static-ip-manifests.sh` | Create NetworkManager static IP configs |
| `generate-core-password-manifest.sh` | Set console access password for core user |
| `generate-vsphere-creds-manifest.sh` | Inject vSphere credentials |
| `generate-console-password-manifests.sh` | Set up OpenShift console authentication |
| `inject-static-ips-into-ignition.sh` | Direct ignition file modification for static IPs |
| `load-vcenter-env.sh` | Load vSphere environment variables |

## Usage Examples

### Deploy New Cluster
```bash
./scripts/rebuild-cluster.sh clusters/ocp416.yaml
```

### Delete Cluster (with confirmation)
```bash
./scripts/delete-cluster.sh clusters/ocp416.yaml
```

### Delete Cluster (force, no confirmation)
```bash
./scripts/delete-cluster.sh --force clusters/ocp416.yaml
```

### Deploy VMs Only
```bash
./scripts/deploy-vms.sh clusters/ocp416.yaml
```

## Monitoring Installation

### Bootstrap Progress
```bash
cd install-configs/ocp416
openshift-install wait-for bootstrap-complete --log-level debug
```

### Installation Completion
```bash
openshift-install wait-for install-complete --log-level debug
```

### Access Cluster
```bash
export KUBECONFIG=install-configs/ocp416/auth/kubeconfig
oc get nodes
oc get co  # Check cluster operators
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

### Common Issues

**VMs not getting static IPs:**
- Check manifest backup in `install-configs/ocp416/manifests-backup-*/`
- Verify DNS servers are reachable
- Check NetworkManager logs: `sudo journalctl -u NetworkManager`

**Bootstrap timeout:**
- Check HAProxy configuration for port 22623
- Verify masters can reach bootstrap: `curl -k https://192.168.42.30:22623/config/master`
- Check master kubelet logs: `sudo journalctl -u kubelet.service`

**DNS resolution issues:**
- Test DNS from VMs: `nslookup quay.io`
- Check `/etc/resolv.conf` on VMs
- Verify DNS servers in cluster YAML

### Debug Commands
```bash
# Check VM IPs
govc vm.ip ocp416-bootstrap
govc vm.ip ocp416-master-0

# Check cluster status
oc get nodes
oc get csr
oc get co

# Check logs
ssh core@192.168.42.30 'sudo journalctl -u bootkube.service'
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
│   ├── rebuild-cluster.sh
│   ├── delete-cluster.sh
│   ├── deploy-cluster.sh
│   ├── deploy-vms.sh
│   └── [other scripts...]
├── install-configs/
│   └── ocp416/
│       ├── *.ign
│       ├── auth/
│       └── manifests-backup-*/
├── govc.env
└── README.md
```

## Security Notes

- Never commit sensitive files (credentials, pull secrets, private keys)
- Use `.gitignore` to exclude sensitive assets
- Rotate passwords and certificates regularly
- Follow Red Hat and VMware security best practices

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with detailed description

## License

Use it or don't use it.   You don't need to pay me but don't complain either

## Support

- [Red Hat OpenShift Documentation](https://docs.openshift.com/)
- [VMware vSphere Documentation](https://docs.vmware.com/en/VMware-vSphere/)
- [OpenShift on vSphere Guide](https://docs.openshift.com/container-platform/4.16/installing/installing_vsphere/)
