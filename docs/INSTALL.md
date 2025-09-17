# Kubernetes Installation and Configuration Guide

This document provides detailed instructions for setting up a Kubernetes cluster on Proxmox VE using our automated scripts. It includes architecture overview, prerequisites, step-by-step setup instructions, troubleshooting, and maintenance procedures.

## Architecture Overview

```
┌──────────────────┐      ┌──────────────────┐
│   Master Node    │      │   Worker Node    │
│  192.168.20.51  │      │  192.168.20.52   │
│                 │      │                  │
│ - Control Plane │      │ - kubelet        │
│ - etcd          │      │ - kube-proxy     │
│ - kubelet       │      │ - containerd     │
│ - kube-proxy    │      │ - Calico agent   │
│ - containerd    │      │                  │
│ - Calico agent  │      │                  │
└────────┬────────┘      └──────────┬───────┘
         │                          │
         │      ┌──────────────┐    │
         └──────┤ Calico CNI   ├────┘
                │ 192.168.0.0/16│
                └──────────────┘
```

## Prerequisites

### System Requirements

- **Master Node:**
  - 2 CPU cores
  - 2GB RAM
  - 20GB disk space
  - Debian 12 (Bookworm)

- **Worker Node:**
  - 2 CPU cores
  - 2GB RAM
  - 20GB disk space
  - Debian 12 (Bookworm)

### Network Requirements

- Static IP addresses for both nodes
- Unrestricted communication between nodes
- Internet access for package installation
- Open ports:
  - Master: 6443, 2379-2380, 10250-10252
  - Worker: 10250, 30000-32767

## Step-by-Step Setup

### 1. Node Preparation

#### 1.1 Locale Setup
```bash
# Run on both nodes
./scripts/setup-locales.sh
```

This script:
- Installs locales package
- Configures en_US.UTF-8
- Sets up SSH to handle locale properly

#### 1.2 Container Runtime
```bash
# Run on both nodes
./scripts/setup-container-runtime.sh
```

This script:
- Loads required kernel modules (overlay, br_netfilter)
- Configures system parameters for container networking
- Installs and configures containerd
- Sets up systemd cgroup driver

#### 1.3 Kubernetes Components
```bash
# Run on both nodes
./scripts/install-kubernetes.sh
```

This script:
- Adds Kubernetes repositories
- Installs kubeadm, kubelet, and kubectl
- Holds package versions to prevent unintended upgrades

#### 1.4 CNI Setup
```bash
# Run on both nodes
./scripts/setup-node-complete.sh
```

This script:
- Installs CNI plugins
- Sets up Calico CNI binary
- Configures CNI directories and symlinks

### 2. Cluster Initialization

#### 2.1 Initialize Master
```bash
# Run from your workstation
./scripts/init-cluster.sh
```

This script:
- Initializes the Kubernetes control plane
- Sets up kubectl configuration
- Installs and configures Calico CNI
- Waits for control plane components to be ready
- Generates join command for worker nodes

#### 2.2 Join Worker Node
The init-cluster.sh script automatically:
- Copies join command to worker node
- Executes join command
- Verifies node has joined successfully

### 3. Verification Steps

#### 3.1 Check Node Status
```bash
kubectl get nodes -o wide
```

Expected output:
```
NAME          STATUS   ROLES           AGE     VERSION   INTERNAL-IP      
k8s-master    Ready    control-plane   10m     v1.28.15  192.168.20.51   
k8s-worker01  Ready    <none>          5m      v1.28.15  192.168.20.52   
```

#### 3.2 Check System Pods
```bash
kubectl get pods -n kube-system
```

Verify all pods are running:
- calico-kube-controllers
- calico-node
- coredns
- etcd
- kube-apiserver
- kube-controller-manager
- kube-proxy
- kube-scheduler

## Troubleshooting

### Common Issues

#### 1. Node Not Ready
```bash
# Check kubelet status
systemctl status kubelet

# Check CNI configuration
ls -l /opt/cni/bin/
ls -l /usr/lib/cni/

# Check logs
journalctl -u kubelet -n 100
```

#### 2. Pod Network Issues
```bash
# Check Calico pods
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check Calico logs
kubectl logs -n kube-system -l k8s-app=calico-node
```

#### 3. Container Runtime Issues
```bash
# Check containerd status
systemctl status containerd

# Check logs
journalctl -u containerd
```

## Maintenance

### Regular Tasks

1. **Update Node Components:**
   ```bash
   # On all nodes
   apt-get update
   apt-get upgrade
   ```

2. **Check Cluster Health:**
   ```bash
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

3. **Monitor Resources:**
   ```bash
   kubectl top nodes
   kubectl top pods --all-namespaces
   ```

### Backup Procedures

1. **Backup etcd:**
   ```bash
   ETCDCTL_API=3 etcdctl snapshot save snapshot.db
   ```

2. **Backup Certificates:**
   ```bash
   tar -czf /backup/k8s-certs.tar.gz /etc/kubernetes/pki
   ```

### Upgrade Procedures

1. **Upgrade Master Node:**
   ```bash
   # On master node
   kubeadm upgrade plan
   kubeadm upgrade apply v1.xx.xx
   ```

2. **Upgrade Worker Nodes:**
   ```bash
   # On worker nodes
   kubeadm upgrade node
   ```

## Security Best Practices

1. **Network Security:**
   - Use network policies to restrict pod communication
   - Enable encryption for pod-to-pod traffic
   - Configure secure etcd communication

2. **Authentication:**
   - Use RBAC for access control
   - Implement certificate rotation
   - Use strong authentication methods

3. **System Hardening:**
   - Minimize installed packages
   - Regular security updates
   - Proper firewall configuration

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Calico Documentation](https://docs.projectcalico.org/)
- [containerd Documentation](https://containerd.io/docs/)