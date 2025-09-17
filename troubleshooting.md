# Kubernetes on Debian 13 - Troubleshooting Guide

This document covers common issues encountered during Kubernetes setup on Debian 13 with containerd and their solutions.

## Table of Contents

1. [Disk Space Issues](#disk-space-issues)
2. [CNI Plugin Path Issues](#cni-plugin-path-issues)
3. [Memory Issues](#memory-issues)
4. [Node Not Ready](#node-not-ready)
5. [Image Pull Errors](#image-pull-errors)
6. [Calico Installation Issues](#calico-installation-issues)
7. [Container Runtime Issues](#container-runtime-issues)

## Disk Space Issues

### Problem
- Nodes showing disk pressure
- `df -h` shows root filesystem at 100%
- Pods failing with `DiskPressure` taint
- Error: "no space left on device"

### Solution

1. **Immediate Cleanup**:
```bash
# Clean journal logs (biggest quick win)
sudo journalctl --vacuum-size=50M

# Remove old containers
sudo crictl ps -a | grep Exited | awk '{print $1}' | xargs -r sudo crictl rm

# Remove unused images
sudo crictl rmi --prune

# Clean apt cache
sudo apt clean
sudo rm -rf /var/cache/apt/archives/*

# Check what's using space
sudo du -sh /var/* | sort -rh | head -10
```

2. **Expand Disk (for VMs)**:
```bash
# First expand disk in hypervisor (Proxmox/VMware/etc)
# Then inside VM:

# Install tools
sudo apt update && sudo apt install -y cloud-guest-utils e2fsprogs

# Grow partition
sudo growpart /dev/sda 1

# Resize filesystem
sudo resize2fs /dev/sda1

# Verify
df -h /
```

3. **Prevention**:
- Start with at least 20GB disk for all nodes
- Set up log rotation
- Monitor disk usage regularly

## CNI Plugin Path Issues

### Problem
- Pods stuck in `ContainerCreating` state
- Error: "failed to find plugin "calico" in path [/usr/lib/cni]"
- Network sandbox creation failures

### Solution

1. **Create Symlinks**:
```bash
# Check where CNI plugins are installed
ls -la /opt/cni/bin/

# Create directory and symlinks
sudo mkdir -p /usr/lib/cni
sudo ln -s /opt/cni/bin/* /usr/lib/cni/

# Specifically for Calico (after calico-node runs)
sudo ln -s /opt/cni/bin/calico /usr/lib/cni/calico
sudo ln -s /opt/cni/bin/calico-ipam /usr/lib/cni/calico-ipam

# Restart kubelet
sudo systemctl restart kubelet
```

2. **Verify CNI Installation**:
```bash
# Check calico-node logs
kubectl logs -n calico-system -l k8s-app=calico-node -c install-cni

# Verify binaries exist
ls -la /opt/cni/bin/calico*
ls -la /usr/lib/cni/calico*
```

## Memory Issues

### Problem
- Master node OOM (Out of Memory) errors
- Pods being evicted
- System becoming unresponsive
- kubelet crashing

### Solution

1. **Increase Memory**:
- Master nodes: Minimum 4GB, recommended 8GB
- Worker nodes: Minimum 2GB, recommended 4GB

2. **Configure Memory Limits**:
```bash
# Edit kubelet config
sudo nano /var/lib/kubelet/config.yaml

# Add:
systemReserved:
  memory: 256Mi
kubeReserved:
  memory: 512Mi
evictionHard:
  memory.available: "100Mi"
  
# Restart kubelet
sudo systemctl restart kubelet
```

3. **Monitor Memory Usage**:
```bash
# Check memory
free -h
kubectl top nodes

# Check container memory
sudo crictl stats
```

## Node Not Ready

### Problem
- Nodes showing `NotReady` status
- Network plugin not initialized
- Runtime network not ready

### Solution

1. **Check Node Status**:
```bash
kubectl describe node <node-name> | grep -A5 Conditions
kubectl get events --field-selector involvedObject.name=<node-name>
```

2. **Common Fixes**:
```bash
# Restart kubelet
sudo systemctl restart kubelet

# Check kubelet logs
journalctl -u kubelet -f

# Verify container runtime
sudo systemctl status containerd
sudo crictl version
```

3. **Network Plugin Issues**:
```bash
# Check if CNI config exists
ls -la /etc/cni/net.d/

# Check Calico pods
kubectl get pods -n calico-system -o wide

# Restart Calico pods if needed
kubectl delete pods -n calico-system --all
```

## Image Pull Errors

### Problem
- `ErrImagePull` or `ImagePullBackOff`
- Timeout pulling images
- Rate limiting from Docker Hub

### Solution

1. **Manual Image Pull**:
```bash
# Pre-pull images on affected node
sudo crictl pull docker.io/calico/node:v3.26.1
sudo crictl pull docker.io/calico/cni:v3.26.1
sudo crictl pull docker.io/calico/typha:v3.26.1

# List images
sudo crictl images
```

2. **Check Connectivity**:
```bash
# Test DNS
nslookup docker.io
ping -c 4 registry-1.docker.io

# Test image pull
sudo crictl pull nginx:alpine
```

3. **Configure Proxy (if needed)**:
```bash
# Edit containerd service
sudo systemctl edit containerd

# Add:
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
Environment="NO_PROXY=localhost,127.0.0.1,10.0.0.0/8,192.168.0.0/16"

# Restart
sudo systemctl restart containerd
```

## Calico Installation Issues

### Problem
- Calico pods not starting
- IP allocation failures
- Network policies not working

### Solution

1. **Check Calico Status**:
```bash
# Check all Calico pods
kubectl get pods -n calico-system

# Check Calico node status
kubectl exec -n calico-system -l k8s-app=calico-node -- calico-node status

# Check IP pools
kubectl get ippool -o yaml
```

2. **Common Fixes**:
```bash
# Restart Calico pods
kubectl delete pods -n calico-system --all

# Check for correct CIDR
kubectl get installation default -o yaml | grep cidr

# Verify Felix configuration
kubectl get felixconfiguration default -o yaml
```

3. **Reset Calico (last resort)**:
```bash
# Delete Calico
kubectl delete -f calico-typha.yaml
kubectl delete -f custom-resources.yaml
kubectl delete -f tigera-operator.yaml

# Clean up CNI
sudo rm -rf /etc/cni/net.d/*

# Reinstall
kubectl create -f tigera-operator.yaml
kubectl create -f custom-resources.yaml
kubectl apply -f calico-typha.yaml
```

## Container Runtime Issues

### Problem
- containerd not responding
- Failed to create pod sandbox
- CRI errors

### Solution

1. **Check containerd Status**:
```bash
# Check service
sudo systemctl status containerd

# Check logs
journalctl -u containerd -f

# Test with crictl
sudo crictl ps
sudo crictl version
```

2. **Fix containerd Configuration**:
```bash
# Regenerate config
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Ensure SystemdCgroup is enabled
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart
sudo systemctl restart containerd
```

3. **Clean Runtime State**:
```bash
# Stop containerd
sudo systemctl stop containerd

# Clean up state
sudo rm -rf /var/lib/containerd/io.containerd.grpc.v1.cri/sandboxes/*
sudo rm -rf /var/lib/containerd/io.containerd.runtime.v2.task/k8s.io/*

# Start containerd
sudo systemctl start containerd
```

## General Debugging Commands

### Useful Commands for Troubleshooting

```bash
# Node debugging
kubectl describe node <node-name>
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Pod debugging
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# System logs
journalctl -u kubelet -f
journalctl -u containerd -f
dmesg -T | tail -50

# Resource usage
kubectl top nodes
kubectl top pods --all-namespaces
df -h
free -h

# Network debugging
ip addr show
ip route show
iptables -L -n -v
conntrack -L

# Container runtime
sudo crictl ps -a
sudo crictl logs <container-id>
sudo crictl exec -it <container-id> sh
```

## Prevention Best Practices

1. **Pre-deployment Checks**:
   - Verify hardware meets minimum requirements
   - Ensure network connectivity between nodes
   - Check DNS resolution
   - Verify time synchronization (NTP)

2. **Regular Maintenance**:
   - Monitor disk usage
   - Set up log rotation
   - Regular system updates
   - Monitor cluster health

3. **Backup Important Components**:
   - etcd backups
   - Kubernetes manifests
   - Cluster certificates

4. **Documentation**:
   - Keep track of custom configurations
   - Document any deviations from standard setup
   - Maintain runbooks for common operations
