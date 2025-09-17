#!/bin/bash

# setup-container-runtime.sh
# This script installs and configures containerd as the container runtime for Kubernetes
# It includes kernel module configuration, sysctl settings, and containerd installation

# Exit on any error
set -e

echo "=== Setting up container runtime (containerd) ==="

echo "1. Loading required kernel modules..."
# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# Load modules immediately and verify
echo "1.1. Loading overlay module..."
sudo modprobe overlay
if ! lsmod | grep -q "^overlay"; then
    echo "Failed to load overlay module"
    exit 1
fi

echo "1.2. Loading br_netfilter module..."
sudo modprobe br_netfilter
if ! lsmod | grep -q "^br_netfilter"; then
    echo "Failed to load br_netfilter module"
    exit 1
fi

echo "2. Configuring sysctl parameters..."
# Set up required sysctl params
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl parameters
sudo sysctl --system

echo "3. Installing containerd..."
# Install containerd
sudo apt-get update
sudo apt-get install -y containerd

echo "4. Configuring containerd..."
# Create default containerd configuration
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# Update containerd configuration to use systemd cgroup driver
echo "4.1. Setting systemd cgroup driver..."
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Configure containerd to use the same cgroup driver as kubelet
sudo mkdir -p /etc/systemd/system/containerd.service.d
cat <<EOF | sudo tee /etc/systemd/system/containerd.service.d/override.conf
[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStartPre=/sbin/modprobe br_netfilter
EOF

echo "5. Starting containerd service..."
# Restart and enable containerd
sudo systemctl daemon-reload
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verify containerd is running
if ! systemctl is-active --quiet containerd; then
    echo "ERROR: containerd is not running"
    exit 1
fi

echo "=== Container runtime setup completed successfully ==="