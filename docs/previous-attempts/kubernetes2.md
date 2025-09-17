# Kubernetes on Proxmox with Debian 13 - Complete Setup Guide

This guide creates a 2-node Kubernetes cluster on Proxmox using Debian 13, with console-only access (no SSH).

## Prerequisites

- Proxmox server (192.168.20.40)
- Access to Proxmox root account
- Terraform installed on your local machine

## Architecture

- **k8s-master** (192.168.20.51) - Control plane node
- **k8s-worker01** (192.168.20.52) - Worker node
- Console access only via Proxmox (no SSH)
- Debian 13 with containerd runtime

## Step 1: Create Debian 13 Template on Proxmox

Create the template that will be used for both VMs:

```bash
#!/bin/bash
# create-template.sh
set -e

echo "=== Creating Debian 13 Template on Proxmox ==="

TEMPLATE_ID="9000"
STORAGE="local-zfs"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64-daily.qcow2"

# Check if template already exists
if ssh root@192.168.20.40 "qm status ${TEMPLATE_ID}" &>/dev/null; then
    echo "Template ${TEMPLATE_ID} already exists!"
    exit 0
fi

# Create template on Proxmox
ssh root@192.168.20.40 << 'EOF'
set -e

TEMPLATE_ID="9000"
STORAGE="local-zfs"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64-daily.qcow2"

# Download cloud image
cd /tmp
wget -q --show-progress -O debian-13-cloud.qcow2 "${IMAGE_URL}"

# Create VM
qm create ${TEMPLATE_ID} \
  --name debian-13-cloudinit \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --agent enabled=1,fstrim_cloned_disks=1

# Import disk
qm disk import ${TEMPLATE_ID} debian-13-cloud.qcow2 ${STORAGE}
DISK_NAME=$(qm config ${TEMPLATE_ID} | grep "^unused0:" | cut -d' ' -f2)

# Configure VM
qm set ${TEMPLATE_ID} \
  --scsi0 ${DISK_NAME} \
  --boot c --bootdisk scsi0 \
  --ide2 ${STORAGE}:cloudinit \
  --serial0 socket --vga serial0 \
  --ostype l26

# Resize disk
qm disk resize ${TEMPLATE_ID} scsi0 20G

# Convert to template
qm template ${TEMPLATE_ID}

rm -f debian-13-cloud.qcow2
echo "Template created successfully!"
EOF
```

## Step 2: Terraform Configuration

Create the following Terraform files:

### terraform.tfvars
```hcl
# Proxmox API access - choose one method:

# Method 1: API Token (recommended)
# api_token = "terraform@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Method 2: Username/Password (will prompt for password)
proxmox_user = "root@pam"
# proxmox_password will be prompted

# SSH keys (not used since we're disabling SSH)
ssh_keys = []
```

### main.tf
```hcl
# Proxmox Provider Configuration
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.69.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.20.40:8006/"
  insecure = true
  
  api_token = var.api_token
  username = var.proxmox_user
  password = var.proxmox_password
  
  ssh {
    agent    = true
    username = "root"
  }
}

# Variables
variable "api_token" {
  description = "Proxmox API token"
  type        = string
  default     = ""
}

variable "proxmox_user" {
  description = "Proxmox username"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "ssh_keys" {
  description = "SSH public keys (not used)"
  type        = list(string)
  default     = []
}

variable "vm_network" {
  description = "Network configuration"
  type = object({
    bridge  = string
    subnet  = string
    gateway = string
    dns     = list(string)
  })
  default = {
    bridge  = "vmbr0"
    subnet  = "192.168.20"
    gateway = "192.168.20.1"
    dns     = ["192.168.20.1", "1.1.1.1"]
  }
}

variable "storage" {
  description = "Storage pool"
  type        = string
  default     = "local-zfs"
}

# Cloud-init files for initial configuration
resource "proxmox_virtual_environment_file" "cloud_config_master" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve-5"
  
  source_raw {
    data = templatefile("${path.module}/cloud-init-master.yaml", {
      master_ip = "${var.vm_network.subnet}.51"
      worker_ip = "${var.vm_network.subnet}.52"
    })
    file_name = "k8s-master-cloud-init.yaml"
  }
}

resource "proxmox_virtual_environment_file" "cloud_config_worker" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve-5"
  
  source_raw {
    data = templatefile("${path.module}/cloud-init-worker.yaml", {
      master_ip = "${var.vm_network.subnet}.51"
      worker_ip = "${var.vm_network.subnet}.52"
    })
    file_name = "k8s-worker-cloud-init.yaml"
  }
}

# Master Node
resource "proxmox_virtual_environment_vm" "k8s_master" {
  name        = "k8s-master"
  node_name   = "pve-5"
  vm_id       = 100
  
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"
  
  cpu {
    cores = 2
    type  = "host"
  }
  
  memory {
    dedicated = 3072
  }
  
  agent {
    enabled = true
  }
  
  network_device {
    bridge = var.vm_network.bridge
    model  = "virtio"
  }
  
  disk {
    datastore_id = var.storage
    file_format  = "raw"
    interface    = "scsi0"
    size         = 20
    ssd          = true
    discard      = "on"
  }
  
  serial_device {}
  
  operating_system {
    type = "l26"
  }
  
  initialization {
    datastore_id = var.storage
    
    ip_config {
      ipv4 {
        address = "${var.vm_network.subnet}.51/24"
        gateway = var.vm_network.gateway
      }
    }
    
    dns {
      servers = var.vm_network.dns
    }
    
    user_data_file_id = proxmox_virtual_environment_file.cloud_config_master.id
  }
  
  clone {
    vm_id = 9000
  }
}

# Worker Node
resource "proxmox_virtual_environment_vm" "k8s_worker01" {
  name        = "k8s-worker01"
  node_name   = "pve-5"
  vm_id       = 101
  
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"
  
  cpu {
    cores = 2
    type  = "host"
  }
  
  memory {
    dedicated = 2048
  }
  
  agent {
    enabled = true
  }
  
  network_device {
    bridge = var.vm_network.bridge
    model  = "virtio"
  }
  
  disk {
    datastore_id = var.storage
    file_format  = "raw"
    interface    = "scsi0"
    size         = 20
    ssd          = true
    discard      = "on"
  }
  
  serial_device {}
  
  operating_system {
    type = "l26"
  }
  
  initialization {
    datastore_id = var.storage
    
    ip_config {
      ipv4 {
        address = "${var.vm_network.subnet}.52/24"
        gateway = var.vm_network.gateway
      }
    }
    
    dns {
      servers = var.vm_network.dns
    }
    
    user_data_file_id = proxmox_virtual_environment_file.cloud_config_worker.id
  }
  
  clone {
    vm_id = 9000
  }
}

# Outputs
output "cluster_info" {
  value = {
    master = {
      id      = proxmox_virtual_environment_vm.k8s_master.vm_id
      ip      = "${var.vm_network.subnet}.51"
      name    = proxmox_virtual_environment_vm.k8s_master.name
      console = "ssh root@192.168.20.40 'qm terminal 100'"
    }
    worker01 = {
      id      = proxmox_virtual_environment_vm.k8s_worker01.vm_id
      ip      = "${var.vm_network.subnet}.52"
      name    = proxmox_virtual_environment_vm.k8s_worker01.name
      console = "ssh root@192.168.20.40 'qm terminal 101'"
    }
  }
}
```

### cloud-init-master.yaml
```yaml
#cloud-config
hostname: k8s-master
manage_etc_hosts: false

write_files:
- path: /etc/hosts
  content: |
    127.0.0.1 localhost
    ${master_ip} k8s-master
    ${worker_ip} k8s-worker01

- path: /etc/modules-load.d/k8s.conf
  content: |
    overlay
    br_netfilter

- path: /etc/sysctl.d/k8s.conf
  content: |
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1

- path: /root/init-k8s.sh
  permissions: '0755'
  content: |
    #!/bin/bash
    # Initialize Kubernetes on master
    kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=${master_ip}
    
    # Setup kubectl for root
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    
    # Install Flannel CNI
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    
    # Generate join command
    kubeadm token create --print-join-command > /root/join-command.txt

packages:
- qemu-guest-agent
- curl
- gnupg2
- software-properties-common
- apt-transport-https
- ca-certificates

runcmd:
# Disable swap
- swapoff -a
- sed -i '/ swap / s/^/#/' /etc/fstab

# Load kernel modules
- modprobe overlay
- modprobe br_netfilter
- sysctl --system

# Install containerd
- curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
- echo "deb [arch=amd64] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
- apt-get update
- apt-get install -y containerd.io
- containerd config default > /etc/containerd/config.toml
- sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
- systemctl restart containerd
- systemctl enable containerd

# Install Kubernetes
- curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
- echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
- apt-get update
- apt-get install -y kubelet kubeadm kubectl
- apt-mark hold kubelet kubeadm kubectl
- systemctl enable kubelet

# Enable guest agent
- systemctl enable --now qemu-guest-agent

# Disable SSH
- systemctl disable ssh
- systemctl stop ssh

# Final message
- echo "Master node ready. Run /root/init-k8s.sh to initialize cluster" > /etc/motd
```

### cloud-init-worker.yaml
```yaml
#cloud-config
hostname: k8s-worker01
manage_etc_hosts: false

write_files:
- path: /etc/hosts
  content: |
    127.0.0.1 localhost
    ${master_ip} k8s-master
    ${worker_ip} k8s-worker01

- path: /etc/modules-load.d/k8s.conf
  content: |
    overlay
    br_netfilter

- path: /etc/sysctl.d/k8s.conf
  content: |
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1

packages:
- qemu-guest-agent
- curl
- gnupg2
- software-properties-common
- apt-transport-https
- ca-certificates

runcmd:
# Disable swap
- swapoff -a
- sed -i '/ swap / s/^/#/' /etc/fstab

# Load kernel modules
- modprobe overlay
- modprobe br_netfilter
- sysctl --system

# Install containerd
- curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
- echo "deb [arch=amd64] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
- apt-get update
- apt-get install -y containerd.io
- containerd config default > /etc/containerd/config.toml
- sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
- systemctl restart containerd
- systemctl enable containerd

# Install Kubernetes
- curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
- echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
- apt-get update
- apt-get install -y kubelet kubeadm kubectl
- apt-mark hold kubelet kubeadm kubectl
- systemctl enable kubelet

# Enable guest agent
- systemctl enable --now qemu-guest-agent

# Disable SSH
- systemctl disable ssh
- systemctl stop ssh

# Final message
- echo "Worker node ready. Get join command from master node" > /etc/motd
```

## Step 3: Deploy Infrastructure

```bash
# 1. Create the template
./create-template.sh

# 2. Initialize Terraform
terraform init

# 3. Deploy VMs (will prompt for Proxmox password)
terraform apply

# 4. Wait for cloud-init to complete (about 5-10 minutes)
echo "Waiting for VMs to initialize..."
sleep 300
```

## Step 4: Initialize Kubernetes Cluster

### On Master Node:
```bash
# Access master console
ssh root@192.168.20.40 'qm terminal 100'

# In the console, run:
/root/init-k8s.sh

# Get the join command
cat /root/join-command.txt
```

### On Worker Node:
```bash
# Access worker console  
ssh root@192.168.20.40 'qm terminal 101'

# In the console, paste the join command from master
# Example:
kubeadm join 192.168.20.51:6443 --token xxxxx --discovery-token-ca-cert-hash sha256:xxxxx
```

## Step 5: Verify Cluster

On the master node console:
```bash
# Check nodes
kubectl get nodes

# Check pods
kubectl get pods --all-namespaces

# Deploy a test application
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc nginx
```

## Console Access Helper Script

Create this script for easy console access:

```bash
#!/bin/bash
# console-access.sh

case $1 in
  master)
    ssh -t root@192.168.20.40 "qm terminal 100"
    ;;
  worker|worker01)
    ssh -t root@192.168.20.40 "qm terminal 101"
    ;;
  *)
    echo "Usage: $0 [master|worker]"
    echo "Example: $0 master"
    exit 1
    ;;
esac
```

## Troubleshooting

### Check VM Status
```bash
ssh root@192.168.20.40 "qm list | grep -E '100|101'"
```

### Check Cloud-Init Status
In the VM console:
```bash
cloud-init status
journalctl -u cloud-init-local
```

### Reset and Redeploy
```bash
terraform destroy -auto-approve
terraform apply -auto-approve
```

## Security Notes

- No SSH access on VMs (disabled by cloud-init)
- Console access only through Proxmox
- All configuration automated through cloud-init
- Suitable for lab/testing environments

## Next Steps

1. Configure persistent storage (Longhorn, OpenEBS, etc.)
2. Install Ingress controller
3. Set up monitoring (Prometheus/Grafana)
4. Deploy applications
