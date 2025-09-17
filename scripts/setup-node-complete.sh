#!/bin/bash

# This script combines all setup steps for creating a Kubernetes node

# 1. Set up locales
./setup-locales.sh

# 2. Set up container runtime
./setup-container-runtime.sh

# 3. Install Kubernetes packages
./install-kubernetes.sh

# 4. Set up CNI plugins
mkdir -p /opt/cni/bin
cd /opt/cni/bin
curl -O -L https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
tar -xvf cni-plugins-linux-amd64-v1.3.0.tgz
rm cni-plugins-linux-amd64-v1.3.0.tgz

# Download and install Calico CNI binary
cd /tmp
curl -L -O https://github.com/projectcalico/cni-plugin/releases/download/v3.20.6/calico-amd64
mkdir -p /opt/cni/bin
mv calico-amd64 /opt/cni/bin/calico
chmod +x /opt/cni/bin/calico

# Create symbolic links
mkdir -p /usr/lib/cni
ln -sf /opt/cni/bin/* /usr/lib/cni/