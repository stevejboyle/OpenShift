#!/bin/bash

set -e

export VSPHERE_INSECURE=true

echo "✅ Generating Ignition configs..."

openshift-install create manifests --dir=.
openshift-install create ignition-configs --dir=.
