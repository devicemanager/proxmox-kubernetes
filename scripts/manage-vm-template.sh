#!/bin/bash
# scripts/manage-vm-template.sh - Part of k8s-debian13-containerd-guide
# Manage QEMU VM templates on remote Proxmox host from MacBook
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration - matching your other scripts
PROXMOX_HOST="${PROXMOX_HOST:-192.168.20.40}"
STORAGE="${STORAGE:-local-zfs}"

# Load from .env if exists
[ -f .env ] && source .env

usage() {
    echo "Usage: $0 <command> [options]"
    echo
    echo "Commands:"
    echo "  list                                         - List all VMs and templates"
    echo "  untemplate <template-id> <vm-id>            - Convert VM template to VM"
    echo "  template <vm-id> <template-id>              - Convert VM to template"
    echo "  modify <template-id>                        - Full workflow: untemplate, modify, re-template"
    echo "  console <vm-id>                             - Open VM console"
    echo "  start <vm-id>                               - Start VM"
    echo "  stop <vm-id>                                - Stop VM"
    echo "  exec <vm-id> <command>                      - Execute command via guest agent"
    echo "  ssh <vm-id> [user]                          - SSH to VM (requires IP)"
    echo
    echo "Example:"
    echo "  $0 modify 9000                              - Modify VM template 9000"
    echo "  $0 console 100                              - Open console for VM 100"
    echo "  $0 exec 100 'apt update'                    - Run command via guest agent"
    exit 1
}

# Function to execute commands on remote Proxmox host
remote_exec() {
    ssh root@${PROXMOX_HOST} "$@"
}

# Function to list VMs and templates
list_vms() {
    echo -e "${BLUE}=== QEMU VMs and Templates on ${PROXMOX_HOST} ===${NC}"
    echo
    echo -e "${GREEN}Templates:${NC}"
    remote_exec "qm list | grep -E 'template|VMID' || echo 'No templates found'"
    echo
    echo -e "${GREEN}VMs:${NC}"
    remote_exec "qm list | grep -v template || echo 'No VMs found'"
}

# Get VM IP address
get_vm_ip() {
    local VM_ID=$1
    local IP=$(remote_exec "qm guest cmd ${VM_ID} network-get-interfaces 2>/dev/null | grep -A 5 '\"name\" : \"eth0\"' | grep '\"ip-address\"' | head -1 | cut -d'\"' -f4" || echo "")
    
    if [ -z "$IP" ]; then
        # Try another method
        IP=$(remote_exec "qm config ${VM_ID} | grep -E 'ipconfig0:' | grep -oP 'ip=\K[0-9.]+'" || echo "")
    fi
    
    echo "$IP"
}

# Function to modify a VM template
modify_template() {
    local TEMPLATE_ID=$1
    local TEMP_ID=$((TEMPLATE_ID - 1))
    
    echo -e "${BLUE}=== Modifying VM Template ${TEMPLATE_ID} on ${PROXMOX_HOST} ===${NC}"
    
    # Check if template exists
    if ! remote_exec "qm config ${TEMPLATE_ID} &>/dev/null"; then
        echo -e "${RED}Template ${TEMPLATE_ID} not found!${NC}"
        exit 1
    fi
    
    # Check if it's actually a template
    if ! remote_exec "qm config ${TEMPLATE_ID} | grep -q 'template: 1'"; then
        echo -e "${YELLOW}VM ${TEMPLATE_ID} is not a template!${NC}"
        exit 1
    fi
    
    # Check if temp VM already exists
    if remote_exec "qm config ${TEMP_ID} &>/dev/null"; then
        echo -e "${YELLOW}VM ${TEMP_ID} already exists!${NC}"
        read -p "Delete it? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remote_exec "qm destroy ${TEMP_ID}"
        else
            exit 1
        fi
    fi
    
    # Step 1: Convert to VM
    echo -e "${GREEN}Step 1: Converting template to VM...${NC}"
    remote_exec "qm clone ${TEMPLATE_ID} ${TEMP_ID} --full"
    
    # Step 2: Start VM
    echo -e "${GREEN}Step 2: Starting VM...${NC}"
    remote_exec "qm start ${TEMP_ID}"
    
    # Wait for VM to boot
    echo "Waiting for VM to boot..."
    sleep 10
    
    # Try to get IP
    local IP=$(get_vm_ip ${TEMP_ID})
    if [ -n "$IP" ]; then
        echo -e "${GREEN}VM IP address: ${IP}${NC}"
    fi
    
    # Step 3: Show options
    echo -e "${GREEN}Step 3: VM ready for modifications${NC}"
    echo
    echo "VM ${TEMP_ID} is now running. You can:"
    echo "  1. Open console: $0 console ${TEMP_ID}"
    echo "  2. SSH (if configured): ssh debian@${IP:-<vm-ip>}"
    echo "  3. Execute via guest agent: $0 exec ${TEMP_ID} '<command>'"
    echo "  4. VNC console: ssh -t root@${PROXMOX_HOST} 'qm terminal ${TEMP_ID}'"
    echo
    echo -e "${YELLOW}Quick modifications:${NC}"
    if [ -n "$IP" ]; then
        echo "  - Update packages:"
        echo "    ssh debian@${IP} 'sudo apt update && sudo apt upgrade -y'"
    fi
    echo "  - Via guest agent:"
    echo "    $0 exec ${TEMP_ID} 'apt update && apt upgrade -y'"
    echo
    read -p "Press Enter when done with modifications..."
    
    # Step 4: Stop and clean
    echo -e "${GREEN}Step 4: Preparing for template conversion...${NC}"
    
    # Clean up VM before converting to template
    echo "Cleaning VM..."
    if remote_exec "qm agent ${TEMP_ID} ping &>/dev/null"; then
        # Use guest agent if available
        remote_exec "qm guest exec ${TEMP_ID} -- bash -c '
            apt-get clean 2>/dev/null || yum clean all 2>/dev/null || true
            rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
            find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
            rm -f /root/.bash_history
            history -c
        '" || echo "Guest agent cleaning failed, continuing..."
    fi
    
    # Stop VM
    remote_exec "qm shutdown ${TEMP_ID} || qm stop ${TEMP_ID}"
    sleep 5
    
    # Step 5: Create new template
    echo -e "${GREEN}Step 5: Creating new template...${NC}"
    
    # Backup old template
    local BACKUP_ID=$((TEMPLATE_ID + 1000))
    if remote_exec "qm config ${TEMPLATE_ID} &>/dev/null"; then
        echo "Backing up old template to ${BACKUP_ID}..."
        remote_exec "qm clone ${TEMPLATE_ID} ${BACKUP_ID} --full || true"
    fi
    
    # Remove old template
    remote_exec "qm destroy ${TEMPLATE_ID}"
    
    # Clone to template ID
    remote_exec "qm clone ${TEMP_ID} ${TEMPLATE_ID} --full"
    
    # Convert to template
    remote_exec "qm template ${TEMPLATE_ID}"
    
    # Clean up temp VM
    remote_exec "qm destroy ${TEMP_ID}"
    
    echo -e "${GREEN}✓ Template ${TEMPLATE_ID} has been updated!${NC}"
    
    # Ask about backup
    if remote_exec "qm config ${BACKUP_ID} &>/dev/null"; then
        read -p "Delete backup template ${BACKUP_ID}? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remote_exec "qm destroy ${BACKUP_ID}"
        fi
    fi
}

# Function to untemplate (convert template to VM)
untemplate() {
    local TEMPLATE_ID=$1
    local VM_ID=$2
    
    echo -e "${BLUE}=== Converting Template ${TEMPLATE_ID} to VM ${VM_ID} ===${NC}"
    
    # Check if template exists and is a template
    if ! remote_exec "qm config ${TEMPLATE_ID} 2>/dev/null | grep -q 'template: 1'"; then
        echo -e "${RED}Template ${TEMPLATE_ID} not found or not a template!${NC}"
        exit 1
    fi
    
    # Check if VM ID already exists
    if remote_exec "qm config ${VM_ID} &>/dev/null"; then
        echo -e "${YELLOW}VM ${VM_ID} already exists!${NC}"
        read -p "Delete it? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remote_exec "qm destroy ${VM_ID}"
        else
            exit 1
        fi
    fi
    
    # Clone template to VM
    remote_exec "qm clone ${TEMPLATE_ID} ${VM_ID} --full"
    echo -e "${GREEN}✓ Created VM ${VM_ID} from template ${TEMPLATE_ID}${NC}"
    
    # Ask if user wants to start it
    read -p "Start VM ${VM_ID}? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        remote_exec "qm start ${VM_ID}"
        echo -e "${GREEN}VM started${NC}"
        
        # Try to get IP after boot
        sleep 10
        local IP=$(get_vm_ip ${VM_ID})
        if [ -n "$IP" ]; then
            echo -e "${GREEN}VM IP address: ${IP}${NC}"
            echo "SSH with: ssh debian@${IP}"
        fi
    fi
}

# Function to template (convert VM to template)
template() {
    local VM_ID=$1
    local TEMPLATE_ID=$2
    
    echo -e "${BLUE}=== Converting VM ${VM_ID} to Template ${TEMPLATE_ID} ===${NC}"
    
    # Check if VM exists
    if ! remote_exec "qm config ${VM_ID} &>/dev/null"; then
        echo -e "${RED}VM ${VM_ID} not found!${NC}"
        exit 1
    fi
    
    # Check if it's already a template
    if remote_exec "qm config ${VM_ID} 2>/dev/null | grep -q 'template: 1'"; then
        echo -e "${YELLOW}${VM_ID} is already a template!${NC}"
        exit 1
    fi
    
    # Stop VM if running
    if remote_exec "qm status ${VM_ID} | grep -q running"; then
        echo "Shutting down VM..."
        remote_exec "qm shutdown ${VM_ID} || qm stop ${VM_ID}"
        sleep 5
    fi
    
    # Clean VM before templating (if guest agent is available)
    echo "Cleaning VM..."
    if remote_exec "qm agent ${VM_ID} ping &>/dev/null"; then
        remote_exec "qm start ${VM_ID}"
        sleep 10
        remote_exec "qm guest exec ${VM_ID} -- bash -c '
            apt-get clean 2>/dev/null || yum clean all 2>/dev/null || true
            rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
            find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
            rm -f /root/.bash_history
        ' || true"
        remote_exec "qm shutdown ${VM_ID} || qm stop ${VM_ID}"
        sleep 5
    fi
    
    # If different IDs, clone first
    if [ "${VM_ID}" != "${TEMPLATE_ID}" ]; then
        # Check if template ID already exists
        if remote_exec "qm config ${TEMPLATE_ID} &>/dev/null"; then
            echo -e "${YELLOW}Template ${TEMPLATE_ID} already exists!${NC}"
            read -p "Delete and replace? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                remote_exec "qm destroy ${TEMPLATE_ID}"
            else
                exit 1
            fi
        fi
        
        remote_exec "qm clone ${VM_ID} ${TEMPLATE_ID} --full"
        remote_exec "qm template ${TEMPLATE_ID}"
        
        read -p "Delete source VM ${VM_ID}? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remote_exec "qm destroy ${VM_ID}"
        fi
    else
        remote_exec "qm template ${VM_ID}"
    fi
    
    echo -e "${GREEN}✓ Created template ${TEMPLATE_ID}${NC}"
}

# Open VM console
open_console() {
    local VM_ID=$1
    echo -e "${GREEN}Opening console for VM ${VM_ID}...${NC}"
    ssh -t root@${PROXMOX_HOST} "qm terminal ${VM_ID}"
}

# Execute command in VM via guest agent
exec_in_vm() {
    local VM_ID=$1
    shift
    local COMMAND="$@"
    
    echo -e "${GREEN}Executing in VM ${VM_ID}: ${COMMAND}${NC}"
    
    # Check if VM is running
    if ! remote_exec "qm status ${VM_ID} | grep -q running"; then
        echo -e "${RED}VM ${VM_ID} is not running!${NC}"
        return 1
    fi
    
    # Check if guest agent is available
    if ! remote_exec "qm agent ${VM_ID} ping &>/dev/null"; then
        echo -e "${RED}Guest agent not available! Is qemu-guest-agent installed in the VM?${NC}"
        return 1
    fi
    
    # Execute command
    remote_exec "qm guest exec ${VM_ID} -- bash -c '${COMMAND}'"
}

# SSH to VM
ssh_to_vm() {
    local VM_ID=$1
    local USER=${2:-debian}
    
    # Get IP
    local IP=$(get_vm_ip ${VM_ID})
    if [ -z "$IP" ]; then
        echo -e "${RED}Could not get IP address for VM ${VM_ID}${NC}"
        echo "Make sure the VM is running and has network configured"
        return 1
    fi
    
    echo -e "${GREEN}Connecting to VM ${VM_ID} at ${IP} as ${USER}...${NC}"
    ssh ${USER}@${IP}
}

# Main logic
case "$1" in
    list)
        list_vms
        ;;
        
    untemplate)
        if [ -z "$2" ] || [ -z "$3" ]; then
            usage
        fi
        untemplate $2 $3
        ;;
        
    template)
        if [ -z "$2" ] || [ -z "$3" ]; then
            usage
        fi
        template $2 $3
        ;;
        
    modify)
        if [ -z "$2" ]; then
            usage
        fi
        modify_template $2
        ;;
        
    console)
        if [ -z "$2" ]; then
            usage
        fi
        open_console $2
        ;;
        
    start)
        if [ -z "$2" ]; then
            usage
        fi
        remote_exec "qm start $2"
        echo -e "${GREEN}VM $2 started${NC}"
        ;;
        
    stop)
        if [ -z "$2" ]; then
            usage
        fi
        remote_exec "qm shutdown $2 || qm stop $2"
        echo -e "${GREEN}VM $2 stopped${NC}"
        ;;
        
    exec)
        if [ -z "$2" ] || [ -z "$3" ]; then
            usage
        fi
        VM_ID=$2
        shift 2
        exec_in_vm ${VM_ID} "$@"
        ;;
        
    ssh)
        if [ -z "$2" ]; then
            usage
        fi
        ssh_to_vm $2 $3
        ;;
        
    *)
        usage
        ;;
esac
