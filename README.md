# OpenShift UPI vSphere Deployment Scripts

This repository contains automation scripts to deploy a Red Hat OpenShift cluster using the User-Provisioned Infrastructure (UPI) model on vSphere. It supports end-to-end provisioning, configuration, bootstrap monitoring, taint/label management, and cleanup.

---

## 🔧 Requirements

- macOS or Linux system
- `yq`, `jq`, `govc`, `openshift-install`, `oc`, and `kubectl` installed and in `$PATH`
- vCenter credentials and environment variables (`load-vcenter-env.sh`)
- Red Hat OpenShift pull secret

---

## 📁 Directory Layout

```
OpenShift/
├── clusters/               # Cluster YAML definitions
├── install-configs/        # Generated install directories per cluster
├── scripts/                # Automation scripts
└── README.md
```

---

## 📝 Cluster YAML Format

Each cluster definition must specify the following:

```yaml
clusterName: test
baseDomain: openshift.sboyle.internal
vcenter_server: vcenter1.sboyle.internal
vcenter_username: administrator@vsphere.sboyle.internal
vcenter_datacenter: Lab
vcenter_cluster: Lab Cluster
vcenter_datastore: datastore-SAN1
vcenter_network: OpenShift_192.168.42.0
vcenter_ca_cert_file: ./certs/vcenter-ca.crt
sshKeyFile: ~/.ssh/id_rsa.pub
pullSecretFile: ./pull-secret.json
network:
  cidr: 192.168.42.0/24
node_counts:
  master: 3
  worker: 2
labels:
  master:
    node-role.kubernetes.io/infra: ""
  worker:
    node-role.kubernetes.io/compute: ""
```

---

## 🚀 Primary Workflow

### Rebuild a Cluster

```bash
./scripts/rebuild-cluster.sh clusters/test.yaml
```

This will:
- Load environment variables
- Delete any previous cluster (via `delete-cluster.sh`)
- Generate `install-config.yaml`
- Backup the install-config to `install-configs/<cluster>/backups/`
- Create ignition configs
- Inject vSphere credentials
- Deploy all VMs
- Wait for bootstrap to complete
- Remove the bootstrap VM
- Apply taint fixes
- Label nodes dynamically

---

## 🛠 Available Scripts

| Script                          | Description |
|---------------------------------|-------------|
| `cleanup-bootstrap.sh`         | Deletes the bootstrap node after install |
| `deploy-vms.sh`                | Creates bootstrap/master/worker VMs using govc |
| `fix-cloud-provider-taints.sh` | Removes unwanted taints from control-plane |
| `generate-console-password-manifests.sh` | Creates a manifest with a default kubeadmin password |
| `generate-core-user-password.sh` | Creates a manifest for a "core" user with password login |
| `generate-install-config.sh`   | Builds install-config.yaml from YAML input |
| `generate-vsphere-creds-manifest.sh` | Injects vSphere secrets into manifest |
| `label-nodes.sh`               | Dynamically applies labels to all nodes based on cluster YAML |
| `load-vcenter-env.sh`          | Loads and exports GOVC_* variables |
| `rebuild-cluster.sh`           | One-command full rebuild of the OpenShift cluster |
| `delete-cluster.sh`            | (Optional) Removes previously running VMs and install dirs |

---

## 📦 Backups

The `install-config.yaml` is automatically backed up before ignition creation:
```
install-configs/<cluster>/backups/install-config.<timestamp>.yaml
```

---

## ✅ Status

Stable and complete for local UPI deployments. Extendable for:
- Custom MachineConfigs
- Additional manifests
- Ingress reconfiguration

---

## 📬 Questions?

Contact: `sboyle@paloaltonetworks.com`
