# node.kubernetes Ansible Role

This role installs and configures Kubernetes packages (kubelet, kubeadm, kubectl) and disables swap as required by Kubernetes.

## Tasks performed
- Installs required system packages
- Adds Kubernetes apt repository and key
- Installs kubelet, kubeadm, kubectl
- Holds package versions
- Disables swap and removes swap from /etc/fstab

## Usage
Add to your playbook:

```yaml
- hosts: k8s_nodes
  become: true
  roles:
    - node.kubernetes
```

## Idempotency
All tasks are idempotent and safe to rerun.
