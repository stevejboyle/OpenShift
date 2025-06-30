# OpenShift 4.16 UPI Deployment on vSphere

This project provides a fully automated script suite to deploy an OpenShift 4.16 cluster on a vSphere environment using UPI (User Provisioned Infrastructure). The scripts assume a macOS or Linux host with necessary tools pre-installed.

---

## 📁 Directory Structure

```
OpenShift/
├── clusters/
│   └── cigna-test.yaml               # Your main cluster configuration
├── install-configs/
│   └── cigna-test/                   # Generated install-config and ignition files
├── manifests/                        # Custom manifests if needed
├── scripts/                          # Automation scripts
└── README.md
```

---

## 🚀 Quick Start

### 1. Configure Cluster YAML

Edit or create your cluster YAML in the `clusters/` directory (e.g. `clusters/cigna-test.yaml`).

### 2. Rebuild Cluster

```bash
scripts/rebuild-cluster.sh clusters/cigna-test.yaml
```

This script will:
- Load vCenter environment
- Delete any previous cluster VMs
- Generate `install-config.yaml`
- Generate ignition files
- Create VMs and assign MACs
- Wait for bootstrap to complete
- Delete bootstrap node
- Fix cloud-provider taints
- Apply node labels
- Display the kubeadmin password and login info

---

## 🛠 Required Tools

- `openshift-install`
- `govc`
- `oc`
- `jq`
- `yq` (YAML processor)

---

## 📜 Scripts

| Script                            | Purpose                                                  |
|----------------------------------|----------------------------------------------------------|
| `rebuild-cluster.sh`             | Main orchestration script                                |
| `generate-install-config.sh`     | Creates `install-config.yaml` dynamically                |
| `generate-vsphere-creds-manifest.sh` | Injects vSphere creds into manifests                 |
| `deploy-vms.sh`                  | Clones and configures all VMs from a base template       |
| `cleanup-bootstrap.sh`           | Deletes the bootstrap VM after ignition completes        |
| `fix-cloud-provider-taints.sh`   | Removes cloud-provider taints from master nodes          |
| `label-nodes.sh`                 | Dynamically labels nodes using cluster YAML              |
| `load-vcenter-env.sh`            | Sources `GOVC_*` env vars needed by govc                 |
| `delete-cluster.sh`              | Deletes all cluster-related VMs in vCenter               |

---

## 📂 Output

After successful run:
- Ignition files are in `install-configs/<clusterName>/`
- VM objects are created under `/Lab/vm/OpenShift/<clusterName>/`
- Console and `kubeadmin` login info is displayed

---

## 🔐 Security

- No secrets are stored in version control.
- vSphere password and sensitive configs are sourced securely.

---

## 🧹 Cleanup

To fully delete a cluster:

```bash
scripts/delete-cluster.sh clusters/cigna-test.yaml
```

---

## 📘 Notes

- Assumes DNS and DHCP infrastructure is preconfigured
- Reverse DNS and static DHCP reservations are **strongly** recommended
- Manifests should be placed in `manifests/` if needed, prior to rebuild

---

© 2025 Steve Boyle. Licensed for private cluster automation use.
