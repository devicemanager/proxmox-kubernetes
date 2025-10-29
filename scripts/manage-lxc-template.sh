#!/bin/bash
# scripts/manage-lxc-template.sh - Part of k8s-debian13-containerd-guide
# Manage LXC templates on remote Proxmox host from MacBook
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
    echo "  list                                           - List all LXC containers and templates"
    echo "  untemplate <template-id> <temp-container-id>  - Convert template to container"
    echo "  template <container-id> <template-id>          - Convert container to template"
    echo "  modify <template-id>                           - Full workflow: untemplate, modify, re-template"
    echo "  enter <container-id>                           - Enter a running container"
    echo "  exec <container-id> <command>                  - Execute command in container"
    echo
    echo "Example:"
    echo "  $0 modify 9000                                - Modify template 9000"
    echo "  $0 enter 8999                                 - Enter container 8999"
    echo "  $0 exec 8999 'apt update'                     - Run command in container 8999"
    exit 1
}

# Function to execute commands on remote Proxmox host
remote_exec() {
    ssh root@${PROXMOX_HOST} "$@"
}

# Enter container interactively
enter_container() {
    local CONTAINER_ID=$1
    echo -e "${GREEN}Entering container ${CONTAINER_ID}...${NC}"
    ssh -t root@${PROXMOX_HOST} "pct enter ${CONTAINER_ID}"
}

# Execute command in container
exec_in_container() {
    local CONTAINER_ID=$1
    shift
    local COMMAND="$@"
    echo -e "${GREEN}Executing in container ${CONTAINER_ID}: ${COMMAND}${NC}"
    ssh root@${PROXMOX_HOST} "pct exec ${CONTAINER_ID} -- bash -c '${COMMAND}'"
}

# [Include all the previous functions here: list_containers, modify_template, untemplate, template]
# ... (same as in the previous script)
# Function to list containers and templates
list_containers() {
    echo -e "${BLUE}=== LXC Containers and Templates on ${PROXMOX_HOST} ===${NC}"
    echo
    echo -e "${GREEN}Templates:${NC}"
    remote_exec "pct list | grep -E 'template|VMID' || echo 'No templates found'"
    echo
    echo -e "${GREEN}Containers:${NC}"
    remote_exec "pct list | grep -v template || echo 'No containers found'"
}
# Function to modify a template
modify_template() {
    local TEMPLATE_ID=$1
    local TEMP_ID=$((TEMPLATE_ID - 1))

    echo -e "${BLUE}=== Modifying Template ${TEMPLATE_ID} on ${PROXMOX_HOST} ===${NC}"

    # Check if template exists
    if ! remote_exec "pct config ${TEMPLATE_ID} &>/dev/null"; then
        echo -e "${RED}Template ${TEMPLATE_ID} not found!${NC}"
        exit 1
    fi

    # Check if temp container already exists
    if remote_exec "pct config ${TEMP_ID} &>/dev/null"; then
        echo -e "${YELLOW}Container ${TEMP_ID} already exists!${NC}"
        read -p "Delete it? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remote_exec "pct destroy ${TEMP_ID}"
        else
            exit 1
        fi
    fi

    # Step 1: Convert to container
    echo -e "${GREEN}Step 1: Converting template to container...${NC}"
    remote_exec "pct clone ${TEMPLATE_ID} ${TEMP_ID} --full"
    # Step 2: Start container
    echo -e "${GREEN}Step 2: Starting container...${NC}"
    remote_exec "pct start ${TEMP_ID}"
    sleep 3

    # Step 3: Show options
    echo -e "${GREEN}Step 3: Container ready for modifications${NC}"
    echo
    echo "Container ${TEMP_ID} is now running. You can:"
    echo "  1. Enter container: ssh -t root@${PROXMOX_HOST} 'pct enter ${TEMP_ID}'"
    echo "  2. Execute commands: ssh root@${PROXMOX_HOST} 'pct exec ${TEMP_ID} -- <command>'"
    echo
    echo -e "${YELLOW}Quick modifications:${NC}"
    echo "  - Update packages:"
    echo "    ssh root@${PROXMOX_HOST} 'pct exec ${TEMP_ID} -- apt update && pct exec ${TEMP_ID} -- apt upgrade -y'"
    echo "  - Install software:"
    echo "    ssh root@${PROXMOX_HOST} 'pct exec ${TEMP_ID} -- apt install -y <package>'"
    echo
    read -p "Press Enter when done with modifications..."

    # Step 4: Stop and clean
    echo -e "${GREEN}Step 4: Preparing for template conversion...${NC}"
    remote_exec "pct stop ${TEMP_ID}"

    # Clean up
    echo "Cleaning container..."
    remote_exec "pct start ${TEMP_ID}"
    sleep 2
    remote_exec "pct exec ${TEMP_ID} -- bash -c '
        apt-get clean 2>/dev/null || true
        rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
        find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
        rm -f /root/.bash_history
        history -c
    '"
    remote_exec "pct stop ${TEMP_ID}"

     # Step 5: Create new template
    echo -e "${GREEN}Step 5: Creating new template...${NC}"

    # Backup old template
    local BACKUP_ID=$((TEMPLATE_ID + 1000))
    if remote_exec "pct config ${TEMPLATE_ID} &>/dev/null"; then
        echo "Backing up old template to ${BACKUP_ID}..."
        remote_exec "pct clone ${TEMPLATE_ID} ${BACKUP_ID} --full || true"
    fi

    # Remove old template
    remote_exec "pct destroy ${TEMPLATE_ID}"

    # Clone to template ID
    remote_exec "pct clone ${TEMP_ID} ${TEMPLATE_ID} --full"

    # Convert to template
    remote_exec "pct template ${TEMPLATE_ID}"

    # Clean up temp container
    remote_exec "pct destroy ${TEMP_ID}"

    echo -e "${GREEN}✓ Template ${TEMPLATE_ID} has been updated!${NC}"

    # Ask about backup
    if remote_exec "pct config ${BACKUP_ID} &>/dev/null"; then
        read -p "Delete backup template ${BACKUP_ID}? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remote_exec "pct destroy ${BACKUP_ID}"
        fi
    fi
}

# Function to untemplate (convert template to container)
untemplate() {
    local TEMPLATE_ID=$1
    local CONTAINER_ID=$2

    echo -e "${BLUE}=== Converting Template ${TEMPLATE_ID} to Container ${CONTAINER_ID} ===${NC}"

    # Check if template exists and is a template
    if ! remote_exec "pct config ${TEMPLATE_ID} 2>/dev/null | grep -q 'template: 1'"; then
        echo -e "${RED}Template ${TEMPLATE_ID} not found or not a template!${NC}"
        exit 1
    fi

    # Check if container ID already exists
    if remote_exec "pct config ${CONTAINER_ID} &>/dev/null"; then
        echo -e "${YELLOW}Container ${CONTAINER_ID} already exists!${NC}"
        read -p "Delete it? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remote_exec "pct destroy ${CONTAINER_ID}"
        else
            exit 1
        fi
    fi

    # Clone template to container
    remote_exec "pct clone ${TEMPLATE_ID} ${CONTAINER_ID} --full"
    echo -e "${GREEN}✓ Created container ${CONTAINER_ID} from template ${TEMPLATE_ID}${NC}"

    # Ask if user wants to start it
    read -p "Start container ${CONTAINER_ID}? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        remote_exec "pct start ${CONTAINER_ID}"
        echo -e "${GREEN}Container started${NC}"
        echo "Enter with: ssh -t root@${PROXMOX_HOST} 'pct enter ${CONTAINER_ID}'"
    fi
}

# Function to template (convert container to template)
template() {
    local CONTAINER_ID=$1
    local TEMPLATE_ID=$2

    echo -e "${BLUE}=== Converting Container ${CONTAINER_ID} to Template ${TEMPLATE_ID} ===${NC}"

    # Check if container exists
    if ! remote_exec "pct config ${CONTAINER_ID} &>/dev/null"; then
        echo -e "${RED}Container ${CONTAINER_ID} not found!${NC}"
        exit 1
    fi

    # Check if it's already a template
    if remote_exec "pct config ${CONTAINER_ID} 2>/dev/null | grep -q 'template: 1'"; then
        echo -e "${YELLOW}${CONTAINER_ID} is already a template!${NC}"
        exit 1
    fi

    # Stop container if running
    if remote_exec "pct status ${CONTAINER_ID} | grep -q running"; then
        echo "Stopping container..."
        remote_exec "pct stop ${CONTAINER_ID}"
    fi

    # Clean container before templating
    echo "Cleaning container..."
    remote_exec "pct start ${CONTAINER_ID} || true"
    sleep 2
    remote_exec "pct exec ${CONTAINER_ID} -- bash -c '
        apt-get clean 2>/dev/null || true
        rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
        find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
        rm -f /root/.bash_history
    ' || true"
    remote_exec "pct stop ${CONTAINER_ID} || true"
    # If different IDs, clone first
    if [ "${CONTAINER_ID}" != "${TEMPLATE_ID}" ]; then
        # Check if template ID already exists
        if remote_exec "pct config ${TEMPLATE_ID} &>/dev/null"; then
            echo -e "${YELLOW}Template ${TEMPLATE_ID} already exists!${NC}"
            read -p "Delete and replace? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                remote_exec "pct destroy ${TEMPLATE_ID}"
            else
                exit 1
            fi
        fi

        remote_exec "pct clone ${CONTAINER_ID} ${TEMPLATE_ID} --full"
        remote_exec "pct template ${TEMPLATE_ID}"

        read -p "Delete source container ${CONTAINER_ID}? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remote_exec "pct destroy ${CONTAINER_ID}"
        fi
    else
        remote_exec "pct template ${CONTAINER_ID}"
    fi

    echo -e "${GREEN}✓ Created template ${TEMPLATE_ID}${NC}"
}

# Main logic
case "$1" in
    list)
        list_containers
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
        
    enter)
        if [ -z "$2" ]; then
            usage
        fi
        enter_container $2
        ;;
        
    exec)
        if [ -z "$2" ] || [ -z "$3" ]; then
            usage
        fi
        CONTAINER_ID=$2
        shift 2
        exec_in_container ${CONTAINER_ID} "$@"
        ;;
        
    *)
        usage
        ;;
esac
