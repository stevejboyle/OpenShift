# OpenShift 4.16 UPI Deployment on vSphere – cigna-test

This repository contains scripts and configuration for deploying a Red Hat OpenShift 4.16 cluster using **User-Provisioned Infrastructure (UPI)** on **vSphere** with a DHCP-based IP architecture.

---

## 🧱 Architecture Summary

- **Platform:** vSphere with manual VM provisioning using `govc`
- **IP Assignment:** All nodes use DHCP
  - Bootstrap and masters: DHCP with **reservations**
  - Workers: DHCP with **reservations** (e.g., `.41`, `.42`)
- **DNS:** All forward and reverse records are manually managed via BIND
- **Cluster Name:** `cigna-test`
- **Base Domain:** `openshift.sboyle.internal`

---

## 📁 Folder Structure

```
OpenShift/
├── assets/                        # Pull secrets, SSH keys, certs
├── clusters/                      # YAML defining cluster layout (e.g., cigna-test.yaml)
├── install-configs/              # Generated manifests and config
├── scripts/                       # Deployment automation scripts
├── govc.env                       # vSphere connection variables
└── .vcenterpw                     # Password file (secure)
```

---

## ⚙️ Key Scripts

| Script | Purpose |
|--------|---------|
| `generate-vsphere-creds-manifest.sh` | Generates vsphere credentials manifest |
| `generate-install-config.sh` | Generates `install-config.yaml` with DHCP-based networking |
| `generate-console-password-manifests.sh` | Creates manifest for console access user |
| `generate-core-user-password.sh` | Creates core user credentials |
| `deploy-vms.sh` | Provisions VMs using `govc` with no static IP logic |
| `monitor-bootstrap.sh` | Monitors bootstrap node readiness |
| `rebuild-cluster.sh` | End-to-end rebuild runner (DHCP-ready) |
| `delete-cluster.sh` | Tears down all cluster VMs |
| `validate-credentials.sh` | Validates vCenter access credentials |

> ⚠️ `generate-static-ip-manifests.sh` has been deprecated and removed.

---

## 🧾 DNS & DHCP Notes

- All nodes use DHCP — masters/bootstrap/workers use **reserved MAC→IP** mappings.
- BIND zone files must include A and PTR records for:
  - `api`, `api-int`, `*.apps`, `bootstrap`, `master-*`, `worker-*`, `lb`
- Ensure MAC addresses in `cigna-test.yaml` match your DHCP server reservations.

---

## 🚀 Quick Start

```bash
# Validate vCenter credentials
./scripts/validate-credentials.sh clusters/cigna-test.yaml

# Rebuild the cluster
./scripts/rebuild-cluster.sh clusters/cigna-test.yaml
```

---

## 🔐 Required Secrets

Place the following in `assets/`:
- `ssh-key.pub` – Public SSH key for core user access
- `pull-secret.json` – Red Hat pull secret
- `console-password.txt` – Htpasswd format password file for UI access
- `vcenter1.sboyle.internal.cer` – CA cert for secure vSphere connection

---

## 🧼 Cleanup

```bash
./scripts/delete-cluster.sh clusters/cigna-test.yaml
```

---

## 📌 Notes

- Requires `govc`, `yq`, and `jq` on the system path
- Designed for manual DNS environments and controlled vSphere clusters
