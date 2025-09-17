#!/bin/bash
# Complete deployment script for Proxmox K8s cluster

set -e

echo "=== Kubernetes Cluster Deployment on Proxmox pve-5 ==="
echo "System: 8GB RAM, ZFS storage"
echo ""

# Check prerequisites
if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform not installed"
    echo "Install: brew install terraform"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq not installed"
    echo "Install: brew install jq"
    exit 1
fi

# Check SSH access
echo "Checking Proxmox connectivity..."
if ! ssh root@192.168.20.40 "hostname" &> /dev/null; then
    echo "Error: Cannot SSH to Proxmox"
    echo "Please ensure: ssh root@192.168.20.40 works"
    exit 1
fi

# Create or verify template
echo "Step 1: Checking Debian 13 template..."
if ssh root@192.168.20.40 "qm status 9000" &>/dev/null; then
    echo "Template 9000 already exists ✓"
else
    echo "Creating template..."
    ./create-template.sh
fi

echo ""
echo "Step 2: Setting up Terraform..."

# Check for terraform.tfvars
if [ ! -f terraform/terraform.tfvars ]; then
    cp terraform/terraform.tfvars.example terraform/terraform.tfvars
    echo ""
    echo "IMPORTANT: Edit terraform.tfvars with:"
    echo "1. Your SSH public key"
    echo "2. Either Proxmox password OR API token"
    echo ""
    echo "To create API token, run: ./terraform/setup-api-token.sh"
    echo ""
    exit 1
fi
cd terraform
# Initialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade

# Show plan
echo ""
echo "Step 3: Planning deployment..."
echo "VMs to create:"
echo "- k8s-master: 3GB RAM, 2 CPU, 20GB disk (192.168.20.51)"
echo "- k8s-worker01: 2GB RAM, 2 CPU, 20GB disk (192.168.20.52)"
echo "Total RAM usage: 5GB (leaving 3GB for Proxmox)"
echo ""

terraform plan

# Confirm
echo ""
read -p "Deploy cluster? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

# Deploy
echo "Step 4: Deploying VMs..."
terraform apply -auto-approve

# Wait for Terraform to complete
sleep 5

# Get IPs from Terraform output
echo ""
echo "Getting VM information..."
CLUSTER_INFO=$(terraform output -json cluster_info 2>/dev/null || echo "{}")

if [ "$CLUSTER_INFO" != "{}" ]; then
    MASTER_IP=$(echo "$CLUSTER_INFO" | jq -r '.master.ip')
    WORKER_IP=$(echo "$CLUSTER_INFO" | jq -r '.worker01.ip')
    
    echo ""
    echo "=== Deployment Complete ==="
    echo ""
    echo "VMs created:"
    echo "  Master:   ssh debian@${MASTER_IP}"
    echo "  Worker01: ssh debian@${WORKER_IP}"
    echo ""
    echo "Serial console access from Proxmox:"
    echo "  Master:   qm terminal 100"
    echo "  Worker01: qm terminal 101"
    echo ""
    echo "Next steps:"
    echo "1. Wait ~2 minutes for cloud-init to complete"
    echo "2. SSH to master: ssh debian@${MASTER_IP}"
    echo "3. Follow kubernetes.md to install Kubernetes"
else
    echo ""
    echo "=== Deployment Complete ==="
    echo "Run 'terraform output cluster_info' to see VM details"
fi

echo ""
echo "To destroy: terraform destroy"
