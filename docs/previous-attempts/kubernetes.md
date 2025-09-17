# Kubernetes Cluster on Debian 13 with containerd

This guide provides a production-ready setup for a Kubernetes cluster using Debian 13 (Trixie) with containerd as the container runtime and Calico for networking.

## Prerequisites

### Hardware Requirements

- **Master Node**: 
  - CPU: 2 cores minimum
  - RAM: 4GB minimum (8GB recommended)
  - Disk: 20GB minimum
- **Worker Nodes**: 
  - CPU: 2 cores minimum
  - RAM: 2GB minimum (4GB recommended)
  - Disk: 20GB minimum

### Network Requirements

- Static IP addresses for all nodes
- Network connectivity between all nodes
- Internet access for package downloads

## Initial System Setup (All Nodes)

### 1. Update System and Install Basic Tools

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release

# Install resize tools (important for VM environments)
sudo apt install -y cloud-guest-utils e2fsprogs

# Install network tools
sudo apt install -y net-tools ethtool
```

### 2. Configure Hostname and Hosts File

```bash
# Set hostname (replace with your node name)
sudo hostnamectl set-hostname k8s-master  # or k8s-worker01, k8s-worker02

# Edit hosts file
sudo nano /etc/hosts

# Add all cluster nodes
192.168.20.34 k8s-master
192.168.20.35 k8s-worker01
192.168.20.36 k8s-worker02
```

### 3. Disable Swap

```bash
# Disable swap immediately
sudo swapoff -a

# Disable swap permanently
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Verify
free -h
```

### 4. Configure Kernel Modules and Sysctl

```bash
# Load required modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure sysctl parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl parameters
sudo sysctl --system

# Verify
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

## Install Container Runtime (All Nodes)

### 1. Install containerd

```bash
# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker repository (works for Debian 13)
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update and install containerd
sudo apt update
sudo apt install -y containerd.io
```

### 2. Configure containerd

```bash
# Create default config
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Enable systemd cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verify
sudo systemctl status containerd
```

### 3. Install CNI Plugins

```bash
# Download and install CNI plugins
wget https://github.com/containernetworking/plugins/releases/download/v1.5.1/cni-plugins-linux-amd64-v1.5.1.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.5.1.tgz
rm cni-plugins-linux-amd64-v1.5.1.tgz

# Create symlinks for compatibility (IMPORTANT for Calico)
sudo mkdir -p /usr/lib/cni
sudo ln -s /opt/cni/bin/* /usr/lib/cni/
```

### 4. Install crictl

```bash
VERSION="v1.31.1"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
sudo tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$VERSION-linux-amd64.tar.gz

# Configure crictl
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
EOF
```

## Install Kubernetes (All Nodes)

### 1. Add Kubernetes Repository

```bash
# Add Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

### 2. Install Kubernetes Components

```bash
# Update and install
sudo apt update
sudo apt install -y kubelet kubeadm kubectl

# Hold packages to prevent automatic updates
sudo apt-mark hold kubelet kubeadm kubectl

# Enable kubelet
sudo systemctl enable kubelet
```

## Initialize Kubernetes Cluster (Master Node Only)

### 1. Pre-pull Required Images

```bash
# Pre-pull images to avoid timeout issues
sudo kubeadm config images pull --kubernetes-version=v1.30.6
```

### 2. Initialize the Cluster

```bash
# Initialize with specific pod network CIDR for Calico
sudo kubeadm init --apiserver-advertise-address=192.168.20.34 --pod-network-cidr=10.244.0.0/16 --kubernetes-version=v1.30.6

# Save the join command output!
```

### 3. Configure kubectl

```bash
# For root user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# For regular user (optional)
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

### 4. Verify Master Status

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

## Join Worker Nodes (Worker Nodes Only)

```bash
# Use the join command from master init output
sudo kubeadm join 192.168.20.34:6443 --token <token> --discovery-token-ca-cert-hash <hash>

# If you lost the join command, recreate it on master:
kubeadm token create --print-join-command
```

## Install Calico Network Plugin (Master Node Only)

### 1. Download Calico Manifests

```bash
# Create directory for manifests
mkdir -p ~/calico
cd ~/calico

# Download Calico operator and CRDs
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

# Download typha manifests
wget https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico-typha.yaml
```

### 2. Modify Configuration

```bash
# Edit custom-resources.yaml to match our pod network CIDR
sed -i 's|cidr: 192.168.0.0/16|cidr: 10.244.0.0/16|g' custom-resources.yaml
```

### 3. Apply Calico

```bash
# Install Calico operator
kubectl create -f tigera-operator.yaml

# Wait for operator to be ready
kubectl wait --for=condition=ready pod -l k8s-app=tigera-operator -n tigera-operator --timeout=300s

# Apply custom resources
kubectl create -f custom-resources.yaml

# Apply typha for better scaling
kubectl apply -f calico-typha.yaml
```

### 4. Verify Calico Installation

```bash
# Watch Calico pods come up
kubectl get pods -n calico-system -w

# Check node status
kubectl get nodes

# Verify Calico node status
kubectl exec -n calico-system -l k8s-app=calico-node -- calico-node status
```

### 5. Pre-pull Calico Images on Worker Nodes (Optional but Recommended)

On each worker node:
```bash
# Pre-pull Calico images to speed up deployment
sudo crictl pull docker.io/calico/node:v3.26.1
sudo crictl pull docker.io/calico/cni:v3.26.1
sudo crictl pull docker.io/calico/typha:v3.26.1
```

## Verification

### Test Cluster Functionality

```bash
# Create test deployment
kubectl create deployment nginx --image=nginx --replicas=3

# Expose deployment
kubectl expose deployment nginx --port=80 --type=ClusterIP

# Check pod distribution
kubectl get pods -o wide

# Test pod connectivity
kubectl run test-pod --image=busybox --rm -it --restart=Never -- wget -qO- nginx

# Clean up test resources
kubectl delete deployment nginx
kubectl delete service nginx
```

### Check Cluster Health

```bash
# Check component status
kubectl get componentstatuses

# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system
kubectl get pods -n calico-system

# Check cluster info
kubectl cluster-info
```

## Post-Installation Tasks

### 1. Enable Pod Scheduling on Master (Optional)

```bash
# Remove master taint to allow pod scheduling
kubectl taint nodes k8s-master node-role.kubernetes.io/control-plane:NoSchedule-
```

### 2. Install Metrics Server (Optional)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Edit deployment to add --kubelet-insecure-tls for self-signed certs
kubectl edit deployment metrics-server -n kube-system
```

### 3. Configure Storage (Optional)

```bash
# For local development, you can use local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
```

## Maintenance Commands

### Useful Commands

```bash
# Check cluster resources
kubectl top nodes
kubectl top pods --all-namespaces

# Check logs
kubectl logs -n calico-system -l k8s-app=calico-node
journalctl -u kubelet -f

# Clean up old containers and images
sudo crictl ps -a | grep Exited | awk '{print $1}' | xargs -r sudo crictl rm
sudo crictl rmi --prune

# Clean up disk space
sudo journalctl --vacuum-size=100M
sudo apt clean
```

## Security Considerations

1. Use firewall rules to restrict access to API server (6443) and etcd (2379-2380)
2. Regularly update Kubernetes and system packages
3. Enable RBAC and audit logging
4. Use network policies to restrict pod-to-pod communication
5. Secure etcd with encryption at rest

## Next Steps

- Set up an Ingress Controller (nginx-ingress or traefik)
- Configure persistent storage
- Set up monitoring (Prometheus + Grafana)
- Implement backup strategy for etcd
- Configure cluster autoscaling (if in cloud environment)

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.
