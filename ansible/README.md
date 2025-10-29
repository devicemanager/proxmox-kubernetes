
# Ansible Usage Guide

This folder contains the Ansible roles and playbooks for automated Kubernetes node setup and cluster orchestration. All planned roles and playbooks have been implemented and tested.

## Usage

1. **Configure Inventory**
   - Edit `inventory/hosts.ini` and add the IP addresses of your master and worker nodes under the appropriate groups.

2. **Node Setup**
   - Run the node setup playbook to configure locales, container runtime, and Kubernetes packages:
     ```bash
     ansible-playbook -i inventory/hosts.ini playbooks/node-kubernetes.yml
     ```

3. **CNI (Calico) Setup**
   - Run the CNI playbook to install and verify Calico networking:
     ```bash
     ansible-playbook -i inventory/hosts.ini playbooks/node-cni.yml
     ```

4. **Join Worker Nodes**
   - Run the join-workers playbook to automatically join worker nodes to the cluster:
     ```bash
     ansible-playbook -i inventory/hosts.ini playbooks/join-workers.yml
     ```

5. **Cluster Verification**
   - Use kubectl to verify all nodes and pods are Ready:
     ```bash
     kubectl --kubeconfig=playbooks/ansible_fetched/admin.conf get nodes -o wide
     kubectl --kubeconfig=playbooks/ansible_fetched/admin.conf get pods -A -o wide
     ```

## Playbooks Overview

- `playbooks/node-kubernetes.yml`: Node setup (locales, containerd, k8s)
- `playbooks/node-cni.yml`: CNI setup (Calico)
- `playbooks/join-workers.yml`: Join worker nodes to cluster

## Roles Overview

- `roles/node.locales`: Locale setup
- `roles/node.containerd`: Container runtime setup
- `roles/node.kubernetes`: Kubernetes install/init
- `roles/node.cni`: Calico/CNI setup
