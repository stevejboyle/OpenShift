# OpenShift vSphere Deployment Automation

Automated deployment scripts for installing Red Hat OpenShift on VMware vSphere with enhanced configuration, secure credential handling, and robust cloud provider initialization.

_Last updated: 2025-06-26_

# Features
- ✅ **Automated vSphere VM deployment** using `govc`, with configurable VM sizing per node type (bootstrap, master, worker).
- ✅ **Dynamic VM scaling** for master and worker nodes based on configuration in `cluster.yaml`.
- ✅ **Secure vCenter password handling**, prompted interactively at runtime (or read from a local debug file).
- ✅ **Pre-assignment of MAC addresses** for bootstrap and master nodes (facilitating DHCP reservations), implemented via `govc vm.change` post-creation.
- ✅ **Comprehensive static IP configuration** for worker nodes via MachineConfigs.
- ✅ **Ignition config delivery via HTTP server** (bypassing `guestinfo` size limits).
- ✅ **Custom manifest injection** (vSphere cloud credentials, console authentication via htpasswd).
- ✅ **vCenter CA Certificate Trust:** Installer automatically trusts vCenter certificate provided in `cluster.yaml`.
- ✅ **Cloud provider taint handling** to enable pod scheduling post-install.
- ✅ **vSphere credential and resource validation** before deployment.
- ✅ **RHCOS Live ISO management**, uploading to datastore for VM booting.
- ✅ **Robust bootstrap monitoring**.

# Prerequisites
Ensure you have the following tools installed and available in your PATH:
- [OpenShift installer](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/) (4.16.36+ recommended)
- [govc](https://github.com/vmware/govmomi/tree/master/govc)
- [yq](https://github.com/mikefarah/yq) (version 4.x)
- [jq](https://stedolan.github.io/jq/)
- `mkisofs` (or `genisoimage` on Linux, install with `brew install cdrtools` on macOS)
- `htpasswd` (part of `apache2-utils` on Debian/Ubuntu, `httpd-tools` on RHEL/CentOS/Fedora)
- `python3` (for the simple HTTP server)

# Getting Started
## 1. Setup vSphere Environment Configuration
Create a `govc.env` file in the root of your project to specify vCenter connection details.
**DO NOT include your vCenter password in this file in production environments.** It will be prompted securely. For debugging, you can use `.vcenterpw`.
```bash
cp govc.env.example govc.env
# Edit govc.env:
# export GOVC_URL="[https://vcenter1.your_domain](https://vcenter1.your_domain).internal/sdk"
# export GOVC_USERNAME="administrator@vsphere.local"
# export GOVC_DATACENTER="YourDatacenterName"
# export GOVC_CLUSTER="YourClusterName"
# export GOVC_DATASTORE="your-datastore-name"
# export GOVC_NETWORK="Your_OpenShift_Port_Group"
# export GOVC_FOLDER="/YourDatacenterName/vm/your_openshift_vm_folder" # Base folder for cluster VMs