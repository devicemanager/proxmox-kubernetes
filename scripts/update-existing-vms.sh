#!/bin/bash
# Update password on existing VMs (without recreating)

echo "Setting root password on existing VMs..."

# For each VM
for VMID in 100 101; do
    echo "Updating VM $VMID..."
    ssh root@192.168.20.40 << EOF
        # Set cloud-init password
        qm set ${VMID} --cipassword '$y$j9T$eHbdTPK0hVFCjdHhTew7S.$nf/NOyA8YPNXsMFWbJEyfLOyHlqqhjjPkrCYW7qGZJ4'
        
        # Regenerate cloud-init (might need reboot to take effect)
        qm cloudinit update ${VMID}
        qm reboot ${VMID}
EOF
done

echo "Passwords updated. VMs are rebooted for changes to take effect."
