#!/bin/bash
# Update password on existing VMs (without recreating)

# Source secrets from .env
if [ -f .env ]; then
  source .env
fi

echo "Setting root password on existing VMs..."

# For each VM
for VMID in 100 101; do
    echo "Updating VM $VMID..."
    ssh root@192.168.20.40 << EOF
        # Set cloud-init password
    qm set ${VMID} --cipassword "${ROOT_PASSWORD}"
        
        # Regenerate cloud-init (might need reboot to take effect)
        qm cloudinit update ${VMID}
        qm reboot ${VMID}
EOF
done

echo "Passwords updated. VMs are rebooted for changes to take effect."
