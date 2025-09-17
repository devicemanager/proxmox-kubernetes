#!/bin/bash
# Fix snippets directory issue

echo "Fixing snippets directory on Proxmox..."

ssh root@192.168.20.40 << 'EOF'
# Check current storage configuration
echo "Current storage configuration:"
cat /etc/pve/storage.cfg

# Ensure local storage has snippets enabled
pvesm set local --content vztmpl,iso,backup,snippets

# Create snippets directory if needed
mkdir -p /var/lib/vz/snippets/

# Set proper permissions
chmod 755 /var/lib/vz/snippets/

echo "Snippets directory ready!"
EOF
