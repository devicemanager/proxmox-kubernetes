# Kubernetes on Debian 13 with Containerd - Complete Setup Guide

This guide sets up a 2-node Kubernetes cluster on Proxmox using Debian 13 cloud images with both console and SSH access.

## Prerequisites

- Proxmox VE server (tested with 8.x)
- Terraform installed on your workstation
- SSH key pair (`~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`)

## File Structure

```
k8s-debian13-containerd-guide/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   ├── cloud-init-master.yaml
│   └── cloud-init-worker.yaml
├── scripts/
│   ├── create-template.sh
│   └── init-cluster.sh
├── .env.example
├── .gitignore
└── README.md
```

## Step 1: Create the Template

First, create the Proxmox template with our script:

### scripts/create-template.sh

```bash
#!/bin/bash
# scripts/create-template.sh
set -e

echo "=== Creating Debian 13 Template with Console & SSH Access ==="

TEMPLATE_ID="9000"
STORAGE="local-zfs"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64-daily.qcow2"
PROXMOX_HOST="192.168.20.40"

# Load from .env if exists
[ -f .env ] && source .env

# Generate SSH key if needed
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

SSH_KEY=$(cat ~/.ssh/id_rsa.pub)

ssh root@${PROXMOX_HOST} << EOF
set -e

# Check if template exists
if qm status ${TEMPLATE_ID} &>/dev/null; then
    echo "Template ${TEMPLATE_ID} already exists!"
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo
    if [[ \$REPLY =~ ^[Yy]$ ]]; then
        qm destroy ${TEMPLATE_ID}
    else
        exit 0
    fi
fi

# Download cloud image
cd /tmp
wget -q --show-progress -O debian-cloud.qcow2 "${IMAGE_URL}"

# Create VM
qm create ${TEMPLATE_ID} \
  --name debian13-k8s-template \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --agent enabled=1

# Import disk
qm disk import ${TEMPLATE_ID} debian-cloud.qcow2 ${STORAGE}
DISK_NAME=\$(qm config ${TEMPLATE_ID} | grep "^unused0:" | cut -d' ' -f2)

# Configure VM
qm set ${TEMPLATE_ID} \
  --scsi0 \${DISK_NAME},discard=on \
  --boot c --bootdisk scsi0 \
  --ide2 ${STORAGE}:cloudinit \
  --serial0 socket --vga serial0 \
  --ostype l26

# Set SSH key for cloud-init
echo '${SSH_KEY}' > /tmp/temp-ssh-key.pub
qm set ${TEMPLATE_ID} --sshkeys /tmp/temp-ssh-key.pub
rm -f /tmp/temp-ssh-key.pub

# Resize disk
qm disk resize ${TEMPLATE_ID} scsi0 20G

# Convert to template
qm template ${TEMPLATE_ID}

rm -f debian-cloud.qcow2
echo "Template created successfully!"
EOF
```

Make it executable:
```bash
chmod +x scripts/create-template.sh
```

## Step 2: Environment Configuration

### .env.example

```bash
# .env.example
# Copy to .env and adjust values

# Proxmox settings
PROXMOX_HOST=192.168.20.40
PROXMOX_NODE=pve-5
TEMPLATE_ID=9000
STORAGE=local-zfs

# Console password for VMs
CONSOLE_PASSWORD=changeme

# Network configuration
SUBNET=192.168.20
GATEWAY=192.168.20.1
DNS_SERVERS=192.168.20.1,1.1.1.1

# VM Resources
MASTER_CORES=2
MASTER_MEMORY=4096
WORKER_CORES=2
WORKER_MEMORY=4096
```

### .gitignore

```gitignore
# Local configuration
.env
.env.local
terraform.tfvars

# Terraform
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
terraform.log
crash.log
*.tfplan

# SSH keys
*.pem
*.key
id_rsa*
*.pub

# Temporary files
*.tmp
*.swp
.DS_Store
```

## Step 3: Terraform Configuration

### terraform/variables.tf

```hcl
# Proxmox connection variables
variable "proxmox_host" {
  description = "Proxmox host IP or hostname"
  type        = string
  default     = "192.168.20.40"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-5"
}

# Authentication method 1: Username/Password
variable "proxmox_user" {
  description = "Proxmox user (e.g., root@pam)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
  default     = ""
}

# Authentication method 2: API Token
variable "proxmox_api_token" {
  description = "Proxmox API token (format: user@realm!tokenid=token-secret)"
  type        = string
  sensitive   = true
  default     = ""
}

# Template and VM configuration
variable "template_id" {
  description = "Template VM ID"
  type        = number
  default     = 9000
}

variable "console_password" {
  description = "Console password for local VM access"
  type        = string
  sensitive   = true
}

variable "vm_network" {
  description = "Network configuration for VMs"
  type = object({
    subnet      = string
    gateway     = string
    dns_servers = string
  })
  default = {
    subnet      = "192.168.20"
    gateway     = "192.168.20.1"
    dns_servers = "192.168.20.1,1.1.1.1"
  }
}

variable "master_vm" {
  description = "Master node configuration"
  type = object({
    vmid        = number
    name        = string
    cores       = number
    memory      = number
    disk_size   = string
    ip_suffix   = number
  })
  default = {
    vmid        = 100
    name        = "k8s-master"
    cores       = 2
    memory      = 4096
    disk_size   = "32G"
    ip_suffix   = 51
  }
}

variable "worker_vm" {
  description = "Worker node configuration"
  type = object({
    vmid        = number
    name        = string
    cores       = number
    memory      = number
    disk_size   = string
    ip_suffix   = number
  })
  default = {
    vmid        = 101
    name        = "k8s-worker01"
    cores       = 2
    memory      = 4096
    disk_size   = "32G"
    ip_suffix   = 52
  }
}
```

### terraform/main.tf

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.69.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://${var.proxmox_host}:8006/"
  insecure = true
  
  # Use API token if provided, otherwise use username/password
  api_token = var.proxmox_api_token != "" ? var.proxmox_api_token : null
  username  = var.proxmox_api_token == "" ? var.proxmox_user : null
  password  = var.proxmox_api_token == "" ? var.proxmox_password : null
  
  # SSH connection for certain operations
  ssh {
    agent    = true
    username = "root"
    host     = var.proxmox_host
  }
}

# Cloud-init configuration for master node
resource "proxmox_virtual_environment_file" "cloud_config_master" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node
  
  source_raw {
    data = templatefile("${path.module}/cloud-init-master.yaml", {
      hostname         = var.master_vm.name
      master_ip       = "${var.vm_network.subnet}.${var.master_vm.ip_suffix}"
      worker_ip       = "${var.vm_network.subnet}.${var.worker_vm.ip_suffix}"
      gateway         = var.vm_network.gateway
      dns_servers     = var.vm_network.dns_servers
      console_password = var.console_password
    })
    file_name = "${var.master_vm.name}-cloud-init.yaml"
  }
}

# Cloud-init configuration for worker node
resource "proxmox_virtual_environment_file" "cloud_config_worker" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node
  
  source_raw {
    data = templatefile("${path.module}/cloud-init-worker.yaml", {
      hostname         = var.worker_vm.name
      master_ip       = "${var.vm_network.subnet}.${var.master_vm.ip_suffix}"
      worker_ip       = "${var.vm_network.subnet}.${var.worker_vm.ip_suffix}"
      gateway         = var.vm_network.gateway
      dns_servers     = var.vm_network.dns_servers
      console_password = var.console_password
    })
    file_name = "${var.worker_vm.name}-cloud-init.yaml"
  }
}

# Master node VM
resource "proxmox_virtual_environment_vm" "k8s_master" {
  name        = var.master_vm.name
  node_name   = var.proxmox_node
  vm_id       = var.master_vm.vmid
  description = "Kubernetes master node"

  clone {
    vm_id = var.template_id
  }

  startup {
    order = "1"
  }

  cpu {
    cores = var.master_vm.cores
    type  = "host"
  }

  memory {
    dedicated = var.master_vm.memory
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = "local-zfs"
    size         = 32
    interface    = "scsi0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.vm_network.subnet}.${var.master_vm.ip_suffix}/24"
        gateway = var.vm_network.gateway
      }
    }
    
    user_data_file_id = proxmox_virtual_environment_file.cloud_config_master.id
  }

  lifecycle {
    ignore_changes = [initialization[0].user_data_file_id]
  }
}

# Worker node VM
resource "proxmox_virtual_environment_vm" "k8s_worker" {
  name        = var.worker_vm.name
  node_name   = var.proxmox_node
  vm_id       = var.worker_vm.vmid
  description = "Kubernetes worker node"

  clone {
    vm_id = var.template_id
  }

  startup {
    order = "2"
  }

  cpu {
    cores = var.worker_vm.cores
    type  = "host"
  }

  memory {
    dedicated = var.worker_vm.memory
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = "local-zfs"
    size         = 32
    interface    = "scsi0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.vm_network.subnet}.${var.worker_vm.ip_suffix}/24"
        gateway = var.vm_network.gateway
      }
    }
    
    user_data_file_id = proxmox_virtual_environment_file.cloud_config_worker.id
  }

  lifecycle {
    ignore_changes = [initialization[0].user_data_file_id]
  }
}

# Outputs
output "master_ip" {
  value = "${var.vm_network.subnet}.${var.master_vm.ip_suffix}"
}

output "worker_ip" {
  value = "${var.vm_network.subnet}.${var.worker_vm.ip_suffix}"
}

output "console_access" {
  value = "qm terminal ${var.master_vm.vmid} (user: root/debian, pass: from console_password)"
}
```

### terraform/cloud-init-master.yaml

```yaml
#cloud-config
hostname: ${hostname}
manage_etc_hosts: true

# Set passwords for console access
chpasswd:
  users:
    - name: root
      password: ${console_password}
      type: text
    - name: debian
      password: ${console_password}
      type: text
  expire: false

# Enable console login
bootcmd:
  - echo "pts/0" >> /etc/securetty
  - echo "ttyS0" >> /etc/securetty

# Write configuration files
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

- path: /root/init-cluster.sh
  permissions: '0755'
  content: |
    #!/bin/bash
    set -e
    
    echo "Initializing Kubernetes cluster..."
    kubeadm init \
      --pod-network-cidr=10.244.0.0/16 \
      --apiserver-advertise-address=${master_ip} \
      --control-plane-endpoint=${master_ip}
    
    echo "Configuring kubectl..."
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    
    echo "Installing Flannel CNI..."
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    
    echo "Generating join command..."
    kubeadm token create --print-join-command > /root/join-command.txt
    
    echo "Cluster initialized! Join command saved to /root/join-command.txt"

packages:
- qemu-guest-agent
- curl
- gnupg2
- software-properties-common
- apt-transport-https
- ca-certificates

runcmd:
  # Set passwords (ensure they work)
  - echo "root:${console_password}" | chpasswd
  - echo "debian:${console_password}" | chpasswd
  
  # Enable console auth
  - sed -i 's/^root:[*]/root:/' /etc/shadow || true
  
  # Disable swap
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  
  # Load kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system
  
  # Install containerd
  - curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
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
  
  # Create MOTD
  - |
    cat > /etc/motd << 'MOTD'
    =====================================
    Kubernetes Master Node
    =====================================
    Hostname: ${hostname}
    IP: ${master_ip}
    
    Initialize cluster: /root/init-cluster.sh
    
    Console access: root/debian
    SSH access: debian@ with SSH key
    =====================================
    MOTD
```

### terraform/cloud-init-worker.yaml

```yaml
#cloud-config
hostname: ${hostname}
manage_etc_hosts: true

# Set passwords for console access
chpasswd:
  users:
    - name: root
      password: ${console_password}
      type: text
    - name: debian
      password: ${console_password}
      type: text
  expire: false

# Enable console login
bootcmd:
  - echo "pts/0" >> /etc/securetty
  - echo "ttyS0" >> /etc/securetty

# Write configuration files
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

- path: /root/join-cluster.sh
  permissions: '0755'
  content: |
    #!/bin/bash
    set -e
    
    echo "Joining Kubernetes cluster..."
    echo "Copy the join command from master node (/root/join-command.txt) and run it here"
    echo "Or SSH to master and get it with:"
    echo "  ssh debian@${master_ip} 'sudo cat /root/join-command.txt'"

packages:
- qemu-guest-agent
- curl
- gnupg2
- software-properties-common
- apt-transport-https
- ca-certificates

runcmd:
  # Set passwords (ensure they work)
  - echo "root:${console_password}" | chpasswd
  - echo "debian:${console_password}" | chpasswd
  
  # Enable console auth
  - sed -i 's/^root:[*]/root:/' /etc/shadow || true
  
  # Disable swap
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  
  # Load kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system
  
  # Install containerd
  - curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
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
  
  # Create MOTD
  - |
    cat > /etc/motd << 'MOTD'
    =====================================
    Kubernetes Worker Node
    =====================================
    Hostname: ${hostname}
    IP: ${worker_ip}
    
    Join cluster: /root/join-cluster.sh
    
    Console access: root/debian
    SSH access: debian@ with SSH key
    =====================================
    MOTD
```

### terraform/terraform.tfvars.example

```hcl
# terraform/terraform.tfvars.example
# Copy to terraform.tfvars and adjust values

# Proxmox connection
proxmox_host     = "192.168.20.40"
proxmox_node     = "pve-5"

# Authentication - Choose ONE method:
# Method 1: Username/Password
proxmox_user     = "root@pam"
proxmox_password = "your-proxmox-password"

# Method 2: API Token (comment out user/pass above)
# proxmox_api_token = "root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Template and console access
template_id      = 9000
console_password = "changeme"

# Network configuration
vm_network = {
  subnet      = "192.168.20"
  gateway     = "192.168.20.1"
  dns_servers = "192.168.20.1,1.1.1.1"
}

# VM specifications
master_vm = {
  vmid      = 100
  name      = "k8s-master"
  cores     = 2
  memory    = 4096
  disk_size = "32G"
  ip_suffix = 51
}

worker_vm = {
  vmid      = 101
  name      = "k8s-worker01"
  cores     = 2
  memory    = 4096
  disk_size = "32G"
  ip_suffix = 52
}
```

## Step 4: Helper Scripts

### scripts/init-cluster.sh

```bash
#!/bin/bash
# scripts/init-cluster.sh
# Helper script to initialize the cluster from your workstation

set -e

MASTER_IP="${1:-192.168.20.51}"
WORKER_IP="${2:-192.168.20.52}"

echo "=== Initializing Kubernetes Cluster ==="
echo "Master: ${MASTER_IP}"
echo "Worker: ${WORKER_IP}"

# Initialize master
echo "Initializing master node..."
ssh debian@${MASTER_IP} "sudo /root/init-cluster.sh"

# Get join command
echo "Getting join command..."
JOIN_CMD=$(ssh debian@${MASTER_IP} "sudo cat /root/join-command.txt")

# Join worker
echo "Joining worker node..."
ssh debian@${WORKER_IP} "sudo ${JOIN_CMD}"

# Verify cluster
echo "Verifying cluster..."
ssh debian@${MASTER_IP} "sudo kubectl get nodes"

echo "Cluster initialized successfully!"
```

Make it executable:
```bash
chmod +x scripts/init-cluster.sh
```

## Creating Proxmox API Token (Optional)

If you prefer using API tokens instead of username/password:

```bash
# On Proxmox server, create API token for Terraform
pveum user token add root@pam terraform --privsep=0

# This will output:
# ┌──────────────┬──────────────────────────────────────┐
# │ key          │ value                                │
# ╞══════════════╪══════════════════════════════════════╡
# │ full-tokenid │ root@pam!terraform                   │
# ├──────────────┼──────────────────────────────────────┤
# │ info         │ {"privsep":"0"}                      │
# ├──────────────┼──────────────────────────────────────┤
# │ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
# └──────────────┴──────────────────────────────────────┘

# Use the full token in terraform.tfvars:
# proxmox_api_token = "root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

## Usage Instructions

1. **Setup Environment**
   ```bash
   cp .env.example .env
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit terraform.tfvars with your Proxmox credentials
   ```

2. **Create Template**
   ```bash
   ./scripts/create-template.sh
   ```

3. **Deploy VMs**
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

4. **Access VMs**
   - Console: `ssh -t root@<proxmox-host> 'qm terminal <vmid>'`
   - SSH: `ssh debian@<vm-ip>`
   - Password: Set in `console_password` variable

5. **Initialize Cluster**
   ```bash
   # Option 1: From your workstation
   ./scripts/init-cluster.sh
   
   # Option 2: Manually on master
   ssh debian@192.168.20.51
   sudo /root/init-cluster.sh
   
   # Then on worker with join command
   ssh debian@192.168.20.52
   sudo kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>
   ```

6. **Verify Cluster**
   ```bash
   ssh debian@192.168.20.51 'sudo kubectl get nodes'
   ```

## Troubleshooting

### Cannot login via console
- Ensure you're using the password set in `console_password`
- Try both `root` and `debian` users
- Check cloud-init logs: `sudo cloud-init status --long`

### SSH not working
- Ensure your SSH key exists: `ls ~/.ssh/id_rsa.pub`
- Verify key was added to template
- Check SSH service: `sudo systemctl status ssh`

### Cluster init fails
- Check containerd: `sudo systemctl status containerd`
- Check kubelet: `sudo systemctl status kubelet`
- View logs: `sudo journalctl -xeu kubelet`

### Terraform authentication errors
The provider needs either username/password or API token. Ensure:
- You've set credentials in terraform.tfvars
- For API tokens: Create with `pveum user token add`
- Check connectivity: `curl -k https://<proxmox-host>:8006`

## Security Notes

1. Console passwords are for emergency access only
2. SSH keys are the preferred access method
3. Consider disabling SSH after cluster setup:
   ```bash
   sudo systemctl disable --now ssh
   ```
4. Change default passwords after first login

## Quick Start Summary

```bash
# 1. Clone repo and setup
git clone https://github.com/Wong1dev/k8s-debian13-containerd-guide.git
cd k8s-debian13-containerd-guide
cp .env.example .env
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# 2. Edit terraform.tfvars with your settings

# 3. Create template
./scripts/create-template.sh

# 4. Deploy infrastructure
cd terraform
terraform init
terraform apply

# 5. Initialize cluster
../scripts/init-cluster.sh

# 6. Access cluster
ssh debian@192.168.20.51 'sudo kubectl get nodes'
```

## License

MIT License - see LICENSE file for details
