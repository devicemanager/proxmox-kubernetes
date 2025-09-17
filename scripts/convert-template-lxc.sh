#!/bin/bash
# convert-template-to-lxc.sh - Convert Proxmox template to LXC container and back
set -e

# Configuration
TEMPLATE_ID="${1:-9000}"
TEMP_CONTAINER_ID="${2:-8999}"
PROXMOX_HOST="${PROXMOX_HOST:-192.168.20.40}"
STORAGE="${STORAGE:-local-zfs}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Proxmox Template to LXC Converter ===${NC}"
echo "Template ID: ${TEMPLATE_ID}"
echo "Temporary Container ID: ${TEMP_CONTAINER_ID}"

# Function to check if VM/CT exists
check_exists() {
    local id=$1
    qm status $id &>/dev/null || pct status $id &>/dev/null
}

# Function to check if it's a template
is_template() {
    local id=$1
    if qm config $id &>/dev/null; then
        qm config $id | grep -q "^template: 1"
    elif pct config $id &>/dev/null; then
        pct config $id | grep -q "^template: 1"
    else
        return 1
    fi
}

# Check if this is an LXC template or VM template
if pct config ${TEMPLATE_ID} &>/dev/null; then
    TYPE="lxc"
    echo -e "${GREEN}Detected LXC template${NC}"
elif qm config ${TEMPLATE_ID} &>/dev/null; then
    TYPE="vm"
    echo -e "${YELLOW}This is a VM template, not an LXC container${NC}"
    echo "For VMs, you need to convert differently. Exiting."
    exit 1
else
    echo -e "${RED}Template ${TEMPLATE_ID} not found!${NC}"
    exit 1
fi

# Check if it's actually a template
if ! is_template ${TEMPLATE_ID}; then
    echo -e "${RED}ID ${TEMPLATE_ID} is not a template!${NC}"
    exit 1
fi

# Check if temporary container already exists
if check_exists ${TEMP_CONTAINER_ID}; then
    echo -e "${YELLOW}Container ${TEMP_CONTAINER_ID} already exists!${NC}"
    read -p "Delete it? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pct destroy ${TEMP_CONTAINER_ID}
    else
        exit 1
    fi
fi

echo -e "${GREEN}Converting template to container...${NC}"

# Clone the template to a new container
pct clone ${TEMPLATE_ID} ${TEMP_CONTAINER_ID} --full

echo -e "${GREEN}Container ${TEMP_CONTAINER_ID} created from template${NC}"
echo "You can now modify the container as needed."
echo
echo "Available options:"
echo "1. Start container: pct start ${TEMP_CONTAINER_ID}"
echo "2. Enter container: pct enter ${TEMP_CONTAINER_ID}"
echo "3. Configure: pct set ${TEMP_CONTAINER_ID} [options]"
echo
read -p "Do you want to start the container now? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    pct start ${TEMP_CONTAINER_ID}
    echo -e "${GREEN}Container started${NC}"
    echo "Enter with: pct enter ${TEMP_CONTAINER_ID}"
fi

echo
echo -e "${YELLOW}When done with modifications:${NC}"
echo "Run: $0 --convert-back ${TEMP_CONTAINER_ID} ${TEMPLATE_ID}"
