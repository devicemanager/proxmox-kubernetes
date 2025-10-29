Role: node.containerd
=====================

Purpose
-------
Install and configure containerd on Kubernetes nodes. This role:

- Installs the containerd package
- Ensures kernel modules overlay and br_netfilter are loaded and persisted
- Sets required sysctl parameters for Kubernetes networking
- Generates a default containerd configuration and ensures SystemdCgroup = true
- Creates a systemd drop-in so required modules are loaded before containerd
- Starts and enables the containerd service

Usage
-----
Create or update your inventory so the group `k8s_nodes` lists the IPs or hostnames
of the VMs created by Terraform. Then run:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/node-containerd.yml
```

Testing notes
-------------
Preferred test flow (recommended):

1. Use Terraform to create the VMs (if not already created):
   - cd terraform
   - terraform apply (or use your existing automation)

2. Update `ansible/inventory/hosts.ini` to include the `k8s_nodes` group with the
   VMs' connection details (ansible_user, ansible_ssh_private_key_file, etc.).

3. Run the playbook from repo root (see command above).

Idempotency
-----------
This role uses Ansible modules (apt, copy, sysctl, systemd) so repeated runs are
idempotent. Handlers restart containerd only when configuration changes.
