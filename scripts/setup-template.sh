#!/bin/bash
# Create Debian cloud-init template on Proxmox

PROXMOX_HOST="192.168.20.40"
TEMPLATE_ID="9000"
STORAGE="local-lvm"

echo "=== Creating Debian 13 Template on Proxmox ==="

# Download cloud image
echo "Downloading Debian cloud image..."
ssh root@${PROXMOX_HOST} << 'EOF'
  cd /tmp
  wget -O debian-13-generic-amd64.qcow2 https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64-daily.qcow2
  
  # Create VM
  qm create 9000 --name debian-13-cloudinit --memory 2048 --net0 virtio,bridge=vmbr0 --cores 2
  
  # Import disk
  qm disk import 9000 debian-13-generic-amd64.qcow2 local-lvm
  
  # Configure hardware
  qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
  qm set 9000 --boot c --bootdisk scsi0
  qm set 9000 --ide2 local-lvm:cloudinit
  qm set 9000 --serial0 socket --vga serial0
  qm set 9000 --agent enabled=1,fstrim_cloned_disks=1
  
  # Resize disk
  qm disk resize 9000 scsi0 +5G
  
  # Convert to template
  qm template 9000
  
  # Clean up
  rm -f debian-13-generic-amd64.qcow2
EOF

echo "Template created with ID: ${TEMPLATE_ID}"
