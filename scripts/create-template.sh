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