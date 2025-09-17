#!/bin/bash
# Check if VMs are ready

echo "=== Checking VM Status ==="

# Check if VMs are running
ssh root@192.168.20.40 << 'EOF'
echo "VM Status:"
qm list | grep -E "(100|101)"

echo -e "\nChecking QEMU Guest Agent:"
qm agent 100 ping 2>/dev/null && echo "Master: Guest agent responding" || echo "Master: Guest agent not ready"
qm agent 101 ping 2>/dev/null && echo "Worker: Guest agent responding" || echo "Worker: Guest agent not ready"
EOF
