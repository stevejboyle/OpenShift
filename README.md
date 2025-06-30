# OpenShift 4.x UPI Deployment (vSphere) - Automated Workflow

This repository automates the end-to-end deployment of a Red Hat OpenShift 4.x cluster using a UPI (User Provisioned Infrastructure) approach on vSphere.

---

## 🧱 Project Structure

```
.
├── clusters/                  # Cluster-specific YAML configs (e.g., cigna-test.yaml)
├── install-configs/          # Generated OpenShift install and ignition files
├── manifests/                # Custom OpenShift manifests
├── scripts/                  # Automation scripts
└── README.md
```

---

## 🚀 Deployment Flow

### Prerequisites:
- macOS or Linux with `bash`, `yq`, `oc`, `govc`, `openshift-install`
- vCenter credentials and CA certificate
- DHCP server with reservations for bootstrap + masters
- DNS entries for OpenShift cluster
- A valid Red Hat pull secret
- A public SSH key

### Main Workflow:

1. **Prepare your Cluster YAML**
   - Modify `clusters/cigna-test.yaml` to reflect your environment:
     - Cluster name, base domain
     - vCenter network/storage/cluster
     - Node counts
     - File paths for SSH key, pull secret, and vCenter CA cert

2. **Run the cluster rebuild**
```bash
./scripts/rebuild-cluster.sh clusters/cigna-test.yaml
```

This performs:
- Wipes and regenerates `install-config.yaml`
- Creates OpenShift ignition files
- Injects vSphere credentials into manifests
- Creates VMs (masters, workers, bootstrap)
- Monitors bootstrap status
- Deletes the bootstrap VM after bootstrap completes
- Removes cloud provider taints
- Labels master and worker nodes (based on YAML input)

---

## 🛠️ Custom Scripts

| Script                          | Purpose                                                    |
|---------------------------------|------------------------------------------------------------|
| `generate-install-config.sh`    | Generates `install-config.yaml` from YAML                 |
| `generate-vsphere-creds-manifests.sh` | Adds cloud credentials to OpenShift manifests        |
| `deploy-vms.sh`                 | Deploys bootstrap, master, and worker VMs via `govc`      |
| `cleanup-bootstrap.sh`         | Verifies bootstrap completion and deletes the bootstrap VM |
| `fix-cloud-provider-taints.sh` | Removes `NoSchedule` taint from master nodes              |
| `label-nodes.sh`               | Applies labels defined in cluster YAML                    |

---

## 📡 Example DNS Configuration

Make sure your DNS (forward + reverse) is configured like this:

```text
api.cigna-test.openshift.sboyle.internal.     A   192.168.42.10
*.apps.cigna-test.openshift.sboyle.internal.  A   192.168.42.20
bootstrap.cigna-test.openshift.sboyle.internal. A 192.168.42.30
master-0.cigna-test.openshift.sboyle.internal.  A 192.168.42.31
...
```

---

## 📆 Last Updated

2025-06-30 02:09:17
