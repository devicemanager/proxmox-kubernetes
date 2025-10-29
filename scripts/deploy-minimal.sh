#!/bin/bash
# Minimal deployment script for resource-constrained environment

set -e

echo "=== Minimal K8s Deployment for 8GB Proxmox Host ==="

# Check terraform
if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    brew install terraform
fi

# Initialize
terraform init -upgrade

# Show the plan
echo "Resource allocation:"
echo "- Master: 3GB RAM, 2 CPU, 15GB disk"  
echo "- Worker: 2GB RAM, 2 CPU, 15GB disk"
echo "- Total: 5GB RAM (leaving 3GB for Proxmox)"
echo ""

terraform plan -var-file=terraform.tfvars

read -p "Continue with deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    exit 0
fi

# Deploy
terraform apply -auto-approve -var-file=terraform.tfvars

# Output connection info
echo ""
echo "=== Deployment Complete ==="
terraform output -json cluster_info | jq .
