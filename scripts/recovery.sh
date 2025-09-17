#!/bin/bash
# Recovery script for interrupted Terraform deployment

echo "=== Terraform Deployment Recovery ==="

# Check Proxmox connectivity
if ! ssh root@192.168.20.40 "hostname" &> /dev/null; then
    echo "Error: Cannot connect to Proxmox. Check VPN/network connection."
    exit 1
fi

# Check VM status on Proxmox
echo "Checking VM status on Proxmox..."
VM_STATUS=$(ssh root@192.168.20.40 "qm list" 2>/dev/null)
echo "$VM_STATUS"

# Check Terraform state
echo -e "\nChecking Terraform state..."
RESOURCES=$(terraform state list 2>/dev/null || echo "No state found")
echo "$RESOURCES"

# Provide recovery options
echo -e "\nRecovery options:"
echo "1. Refresh state and continue (if VMs exist)"
echo "2. Destroy and start fresh"
echo "3. Manual recovery"
echo "4. Cancel"

read -p "Choose option (1-4): " choice

case $choice in
    1)
        echo "Refreshing state..."
        terraform refresh
        
        # Check if null_resource needs to be re-run
        if terraform state show null_resource.configure_hosts &> /dev/null; then
            echo "Tainting configuration resource to re-run..."
            terraform taint null_resource.configure_hosts
        fi
        
        echo "Continuing deployment..."
        terraform apply
        ;;
    
    2)
        echo "Destroying existing resources..."
        terraform destroy -auto-approve
        
        echo "Starting fresh deployment..."
        terraform apply
        ;;
    
    3)
        echo "Manual recovery steps:"
        echo "1. Check VMs: ssh root@192.168.20.40 'qm list'"
        echo "2. If VMs exist but not in Terraform:"
        echo "   terraform import proxmox_virtual_environment_vm.k8s_master 100"
        echo "   terraform import proxmox_virtual_environment_vm.k8s_worker01 101"
        echo "3. Re-run provisioning:"
        echo "   terraform taint null_resource.configure_hosts"
        echo "   terraform apply"
        ;;
    
    4)
        echo "Cancelled"
        exit 0
        ;;
esac
