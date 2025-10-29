#!/bin/bash
# convert-lxc-to-template.sh - Convert modified LXC container back to template
set -e

# Configuration
CONTAINER_ID="${1}"
NEW_TEMPLATE_ID="${2}"
STORAGE="${STORAGE:-local-zfs}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$CONTAINER_ID" ] || [ -z "$NEW_TEMPLATE_ID" ]; then
    echo "Usage: $0 <container-id> <new-template-id>"
    exit 1
fi

echo -e "${GREEN}=== LXC to Template Converter ===${NC}"
echo "Container ID: ${CONTAINER_ID}"
echo "New Template ID: ${NEW_TEMPLATE_ID}"

# Check if container exists
if ! pct status ${CONTAINER_ID} &>/dev/null; then
    echo -e "${RED}Container ${CONTAINER_ID} not found!${NC}"
    exit 1
fi

# Check if new template ID already exists
if pct config ${NEW_TEMPLATE_ID} &>/dev/null || qm config ${NEW_TEMPLATE_ID} &>/dev/null; then
    echo -e "${YELLOW}ID ${NEW_TEMPLATE_ID} already exists!${NC}"
    read -p "Delete and replace? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pct destroy ${NEW_TEMPLATE_ID} 2>/dev/null || qm destroy ${NEW_TEMPLATE_ID} 2>/dev/null
    else
        exit 1
    fi
fi

echo -e "${GREEN}Preparing container for template conversion...${NC}"

# Stop container if running
if pct status ${CONTAINER_ID} | grep -q "running"; then
    echo "Stopping container..."
    pct stop ${CONTAINER_ID}
fi

# Clean up container before converting to template
echo "Cleaning up container..."
pct exec ${CONTAINER_ID} -- bash -c '
# Clean package cache
apt-get clean 2>/dev/null || yum clean all 2>/dev/null || true

# Clear logs
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true

# Remove temporary files
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

# Clear bash history
rm -f /root/.bash_history
history -c
' || echo "Some cleanup commands failed (container might be stopped)"

# Create new container from the modified one
echo -e "${GREEN}Creating new template...${NC}"

if [ "${CONTAINER_ID}" != "${NEW_TEMPLATE_ID}" ]; then
    # Clone to new ID
    pct clone ${CONTAINER_ID} ${NEW_TEMPLATE_ID} --full
    
    # Optionally remove the temporary container
    echo
    read -p "Delete temporary container ${CONTAINER_ID}? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pct destroy ${CONTAINER_ID}
    fi
fi

# Convert to template
echo -e "${GREEN}Converting to template...${NC}"
pct template ${NEW_TEMPLATE_ID}

echo -e "${GREEN}✓ Template ${NEW_TEMPLATE_ID} created successfully!${NC}"
echo
echo "You can now use this template to create new containers:"
echo "  pct clone ${NEW_TEMPLATE_ID} <new-id>"
