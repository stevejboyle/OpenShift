# OpenShift UPI Deployment on ESXi

This repository contains scripts and automation to deploy OpenShift (UPI) on VMware ESXi.  
The workflow uses **DHCP for initial boot**, then applies **static IP addresses** via MachineConfigs post-install.

## 🆕 What's New
- **macOS & Linux compatibility** for all scripts (Bash 3.2+ safe).
- **Guestinfo URL Mode** for Ignition files when size exceeds vSphere limits.
- **Automatic Ignition HTTP Server** (port 8088) start/stop inside `rebuild-cluster.sh`.
- **NetworkManager OVS conflict fix** injected via Ignition.
- **Cross-platform base64 handling** (GNU/BSD).
- **Safer quoting & null-safe YAML lookups** in all scripts.
- **Health checks** for Ignition server before VM deployment.

## 📂 Directory Structure
```
scripts/
  cleanup-bootstrap.sh
  delete-cluster.sh
  deploy-vms.sh                # URL-mode capable
  fix-cloud-provider-taints.sh
  generate-install-config.sh
  generate-network-manifests.sh
  label-nodes.sh
  load-vcenter-env.sh
  merge-network-ignition.sh
  rebuild-cluster.sh           # Starts Ignition server on 8088 automatically
  start-ignition-server.sh     # HTTP server helper
install-configs/
  <cluster-name>/              # Generated install configs & Ignition files
clusters/
  <cluster-name>.yaml          # Cluster definition
```

## ⚙️ Deployment Flow
1. **Prepare your `clusters/<name>.yaml`**
   - Example:
     ```yaml
     clusterName: cigna-test
     baseDomain: example.com
     ignition_server:
       host_ip: 192.168.42.10
       port: 8088
     masters: 3
     workers: 2
     node_ips:
       master-0: 192.168.42.11
       master-1: 192.168.42.12
       master-2: 192.168.42.13
       worker-0: 192.168.42.41
       worker-1: 192.168.42.42
     interface: ens192
     ```

2. **Run the rebuild**
   ```bash
   scripts/rebuild-cluster.sh clusters/cigna-test.yaml
   ```

3. **What happens under the hood**
   - Deletes old cluster & cleans install dir.
   - Generates `install-config.yaml`.
   - Runs `openshift-install` to produce Ignition files.
   - Generates network configs to fix OVS issues.
   - Merges network configs into Ignition.
   - **Starts Ignition HTTP server on port 8088**.
   - Deploys VMs (ESXi) with `guestinfo.ignition.config.url` pointing to HTTP server.
   - Waits for bootstrap complete.
   - Optionally cleans up bootstrap node.
   - Waits for operators to stabilize.
   - Applies taint fixes & node labels.
   - Prints cluster access info.

## 🌐 Ignition HTTP Server
- **Port:** 8088
- **Path:** Serves files from `install-configs/<cluster-name>`
- **Test locally:**
  ```bash
  curl -I http://127.0.0.1:8088/
  ```
- **Test remotely (VM network):**
  ```bash
  curl -I http://<host-ip>:8088/bootstrap.ign
  ```

## 🖥️ macOS Notes
- All scripts are compatible with macOS Bash 3.2.
- Ensure the Python binary running the HTTP server is allowed in macOS firewall:
  ```bash
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add $(which python3)
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp $(which python3)
  ```

## 📜 Requirements
- `yq` (v4+)
- `openshift-install` (matching desired OCP release)
- `govc` CLI
- Python 3.x
- ESXi environment prepared with proper networking

## 🚀 Example Commands
```bash
# Start from scratch
scripts/rebuild-cluster.sh clusters/cigna-test.yaml

# Just deploy VMs from an existing Ignition set
scripts/deploy-vms.sh clusters/cigna-test.yaml install-configs/cigna-test
```

---
**Author:** Steve Boyle  
**Last Updated:** 2025-08-12
