
# Proxmox Kubernetes Cluster Automation

This repository automates the deployment of a Kubernetes cluster on Proxmox using **Terraform** and **Ansible**. All node setup and cluster configuration is now handled by idempotent Ansible roles and playbooks. Shell scripts for node setup have been removed.

## Directory Structure

```
proxmox-kubernetes/
├── ansible/
│   ├── inventory/hosts.ini
│   ├── playbooks/
│   │   ├── node-kubernetes.yml
│   │   ├── node-cni.yml
│   │   ├── join-workers.yml
│   └── roles/
│       ├── node.locales/
│       ├── node.containerd/
│       ├── node.kubernetes/
│       └── node.cni/
├── scripts/
│   ├── create-template.sh
│   ├── setup-api-token.sh
│   ├── manage-lxc-template.sh
│   ├── manage-vm-template.sh
│   ├── ... (template/infra management scripts)
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── cloud-init-master.yaml
│   ├── cloud-init-worker.yaml
│   └── ...
├── README.md
├── troubleshooting.md
└── docs/
   └── ...
```


## Quick Start

1. **Prepare Proxmox Template**
   - Run `scripts/create-template.sh` to create a Debian 13 template with cloud-init and SSH access.

2. **Configure API Token**
   - Run `scripts/setup-api-token.sh` to create a Terraform API token for Proxmox.

3. **Edit Terraform Variables**
   - Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and edit with your SSH key and API token.

4. **Deploy Infrastructure**
   - Run `scripts/deploy.sh` to deploy master and worker VMs using Terraform.

5. **Configure Kubernetes Nodes with Ansible**
   - Update the Ansible inventory (`ansible/inventory/hosts.ini`) with the IPs of your master and worker nodes.
   - Run the Ansible playbooks to configure all nodes:
     ```bash
     cd ansible/playbooks
     ansible-playbook -i ../inventory/hosts.ini node-kubernetes.yml
     ansible-playbook -i ../inventory/hosts.ini node-cni.yml
     ```
   - This will set up locales, container runtime, Kubernetes packages, and CNI (Calico) on all nodes.

6. **Join Worker Nodes**
   - Run the join-workers playbook to automatically join worker nodes to the cluster:
     ```bash
     ansible-playbook -i ../inventory/hosts.ini join-workers.yml
     ```

7. **Verify Cluster**
   - Use kubectl to verify all nodes and pods are Ready:
     ```bash
     kubectl --kubeconfig=ansible/playbooks/ansible_fetched/admin.conf get nodes -o wide
     kubectl --kubeconfig=ansible/playbooks/ansible_fetched/admin.conf get pods -A -o wide
     ```

**Note:** The POD network CIDR is set to `192.168.0.0/16` in both the Ansible roles and the Kubernetes/Calico configuration. Ensure your playbooks and manifests use this value for correct pod networking.


## Ansible Roles & Playbooks

- `ansible/roles/node.locales`: Locale configuration
- `ansible/roles/node.containerd`: Container runtime setup
- `ansible/roles/node.kubernetes`: Kubernetes installation and init
- `ansible/roles/node.cni`: CNI (Calico) installation and verification
- `ansible/playbooks/node-kubernetes.yml`: Node setup
- `ansible/playbooks/node-cni.yml`: CNI setup
- `ansible/playbooks/join-workers.yml`: Worker join automation


## Template & VM Management

Scripts for managing Proxmox templates and VMs (creation, conversion, password updates) are still available in `scripts/`. These are for template/infra management only and are not part of the node setup workflow.


## Troubleshooting

- If nodes or pods are not Ready, check the Ansible playbook output for errors.
- Ensure the POD network CIDR is set to `192.168.0.0/16` everywhere (Kubernetes, Calico, Ansible roles).
- For CNI issues, verify that Calico pods are running and CNI plugin binaries are present on all nodes.
- For VM/template issues, use the scripts in `scripts/` to inspect, modify, or recover templates and VMs.
- See `troubleshooting.md` and `docs/` for more details and recovery steps.
# Proxmox Kubernetes Cluster Setup

This repository contains scripts and configuration files for setting up a Kubernetes cluster on Proxmox VE using Terraform.

## Prerequisites

- Proxmox VE 7.0 or later
- Terraform with Proxmox provider
- SSH access to Proxmox host
- Basic understanding of Kubernetes concepts

## Directory Structure

```
.
├── scripts/               # Shell scripts for cluster setup
├── terraform/            # Terraform configuration files
├── kubernetes.md         # Kubernetes setup documentation
└── README.md            # This file
```

## Quick Start

1. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and adjust values
2. Initialize and apply Terraform configuration:
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

## Step by Step Setup

### 1. Infrastructure Setup

1. Create API token in Proxmox:
   ```bash
   ./scripts/create-api-token.sh
   ```

2. Set up VM template:
   ```bash
   ./scripts/setup-template.sh
   ```

3. Deploy VMs using Terraform:
   ```bash
   cd terraform
   terraform apply
   ```

### 2. Node Preparation

1. Set up locales to prevent warnings:
   ```bash
   ./scripts/setup-locales.sh
   ```

2. Install container runtime (containerd):
   ```bash
   ./scripts/setup-container-runtime.sh
   ```

3. Install Kubernetes packages:
   ```bash
   ./scripts/install-kubernetes.sh
   ```

4. Set up CNI plugins:
   ```bash
   ./scripts/setup-node-complete.sh
   ```

Alternatively, you can use the combined script:
```bash
./scripts/setup-node-complete.sh
```

### 3. Cluster Initialization

1. Initialize the cluster:
   ```bash
   ./scripts/init-cluster.sh
   ```

This script will:
- Initialize the master node
- Install Calico CNI
- Join the worker node
- Wait for the cluster to be ready

## Configuration Details

### Network Configuration

- Pod Network CIDR: 192.168.0.0/16 (Calico default)
- Service CIDR: 10.96.0.0/12
- Node IPs:
  - Master: 192.168.20.51
  - Worker: 192.168.20.52

### Components

- Container Runtime: containerd
- CNI Plugin: Calico
- Kubernetes Version: 1.28
- OS: Debian 12 (Bookworm)

## Verification

To verify the cluster is working:

1. Check node status:
   ```bash
   ssh debian@192.168.20.51 'kubectl get nodes'
   ```

2. Check pod status:
   ```bash
   ssh debian@192.168.20.51 'kubectl get pods -A'
   ```

3. Test deployment:
   ```bash
   ssh debian@192.168.20.51 'kubectl create deployment nginx --image=nginx:latest --replicas=2'
   ```

## Troubleshooting

### Common Issues

1. Locale Warnings
   - Run `setup-locales.sh` on both nodes
   - Verify with `locale` command

2. CNI Issues
   - Check CNI binary installation in `/opt/cni/bin`
   - Verify symlinks in `/usr/lib/cni`
   - Check Calico pod status

3. Node Not Ready
   - Check kubelet status: `systemctl status kubelet`
   - Review logs: `journalctl -u kubelet`

## Maintenance

### Adding New Nodes

1. Create new VM using Terraform
2. Run node preparation scripts
3. Get join command from master:
   ```bash
   ssh debian@192.168.20.51 'sudo cat /root/join-command.txt'
   ```
4. Execute join command on new node

### Updating Cluster

1. Update packages on nodes
2. Follow Kubernetes upgrade procedure
3. Update CNI plugin if necessary

## Security Considerations

- API token is stored in Terraform variables
- Node access requires SSH key
- Cluster uses RBAC for authorization
- Network policies can be implemented using Calico

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License