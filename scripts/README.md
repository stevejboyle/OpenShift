# OpenShift vSphere Deployment Automation

Automated deployment scripts for installing Red Hat OpenShift on VMware vSphere with enhanced configuration, secure credential handling, and robust cloud provider initialization.

_Last updated: 2025-06-26_

# Features
- ✅ **Automated vSphere VM deployment** using `govc`, with configurable VM sizing per node type (bootstrap, master, worker).
- ✅ **Secure vCenter password handling**, prompted interactively at runtime (not stored in files).
- ✅ **Pre-assignment of MAC addresses** for bootstrap and master nodes (facilitating DHCP reservations).
- ✅ **Comprehensive static IP configuration** for worker nodes via MachineConfigs.
- ✅ **Ignition config injection via guestinfo** (primary method for nodes).
- ✅ **Custom manifest injection** (vSphere cloud credentials, console authentication via htpasswd).
- ✅ **Dynamic network configuration** from cluster YAML.
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

# Getting Started
## 1. Setup vSphere Environment Configuration
Create a `govc.env` file in the root of your project to specify vCenter connection details.
**DO NOT include your vCenter password in this file.** It will be prompted securely.
```bash
cp govc.env.example govc.env
# Edit govc.env:
# export GOVC_URL="[https://vcenter1.your_domain](https://vcenter1.your_domain).internal/sdk"
# export GOVC_USERNAME="administrator@vsphere.local"
# export GOVC_DATACENTER="YourDatacenterName"
# export GOVC_CLUSTER="YourClusterName"
# export GOVC_DATASTORE="your-datastore-name"
# export GOVC_NETWORK="Your_OpenShift_Port_Group"
# export GOVC_FOLDER="/YourDatacenterName/vm/your_openshift_vm_folder"