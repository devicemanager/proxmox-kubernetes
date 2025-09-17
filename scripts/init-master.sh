#!/bin/bash
set -e

# Create kubeadm configuration
cat << EOF | sudo tee /etc/kubernetes/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: "unix:///var/run/containerd/containerd.sock"
  kubeletExtraArgs:
    node-ip: "192.168.20.51"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  podSubnet: "192.168.0.0/16"  # For Calico
  serviceSubnet: "10.96.0.0/12"
controlPlaneEndpoint: "192.168.20.51:6443"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

# Reset any previous configuration
sudo kubeadm reset -f

# Initialize the control plane
sudo kubeadm init --config /etc/kubernetes/kubeadm-config.yaml

# Configure kubectl for debian user
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config