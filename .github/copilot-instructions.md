## Copilot / AI agent instructions for proxmox-kubernetes

Goal: Help an AI coding agent be immediately productive in this repository by summarizing the architecture, developer workflows, conventions, integration points, and concrete file examples.

- Big picture
  - This repo provisions Proxmox VMs (Terraform) and configures them into a Kubernetes cluster (Ansible). The high-level flow is:
    1. Create/prepare a Debian cloud-init template (scripts/* and `scripts/create-template.sh`).
    2. Provision VMs using Terraform (`terraform/` — see `main.tf`, `terraform.tfvars` and cloud-init YAMLs).
    3. Configure nodes via Ansible roles/playbooks (`ansible/playbooks/*.yml` and `ansible/roles/*`).
  - Important directories: `terraform/`, `ansible/` (inventory, playbooks, roles), and `scripts/` (template & token helpers).

- Key files and examples to inspect
  - `terraform/terraform.tfvars.example` — where API tokens and SSH keys are injected for provisioning.
  - `terraform/cloud-init-master.yaml` and `terraform/cloud-init-worker.yaml` — cloud-init used by Terraform-created VMs.
  - `ansible/inventory/hosts.ini` — canonical inventory used by playbooks.
  - `ansible/playbooks/node-kubernetes.yml` — overall node configuration playbook (locales, containerd, kube packages).
  - `ansible/playbooks/node-cni.yml` — Calico CNI deployment and verification.
  - `ansible/playbooks/join-workers.yml` and `ansible/playbooks/ansible_fetched/*` — join command and `admin.conf` outputs are kept here after runs.
  - `ansible/roles/node.containerd/defaults/main.yml` — container runtime defaults (useful when changing runtime settings).

- Developer workflows (how humans run things)
  - Prepare API token for Terraform: `scripts/setup-api-token.sh` (creates Proxmox API token used in `terraform/terraform.tfvars`).
  - Build template: `scripts/create-template.sh` or `scripts/setup-template.sh` — results are used by Terraform.
  - Provision infra:
    - Either: `cd terraform && terraform init && terraform apply`
    - Or run the helper `scripts/deploy.sh` which wraps Terraform flows in this repo.
  - Configure nodes with Ansible (after provisioning and updating `ansible/inventory/hosts.ini`):
    - `cd ansible/playbooks && ansible-playbook -i ../inventory/hosts.ini node-kubernetes.yml`
    - `ansible-playbook -i ../inventory/hosts.ini node-cni.yml`
    - `ansible-playbook -i ../inventory/hosts.ini join-workers.yml`
  - Verify cluster: `kubectl --kubeconfig=ansible/playbooks/ansible_fetched/admin.conf get nodes -o wide`.

- Project-specific conventions & patterns (not generic advice)
  - Pod network CIDR is fixed to `192.168.0.0/16` across Ansible roles and Calico manifests — if changing the CIDR, update both `ansible/roles/node.kubernetes` and Calico manifests.
  - The repo prefers idempotent Ansible roles over ad-hoc shell node setups; scripts in `scripts/` are primarily for Proxmox template/infra management (not node configuration).
  - Sensitive values (Proxmox API token, SSH private keys) are expected in `terraform/terraform.tfvars` and must NOT be committed.
  - Fetched runtime artifacts (cluster admin kubeconfig and join commands) are stored under `ansible/playbooks/ansible_fetched/` after playbook runs — check that folder when automating verification.

- Integration points and external dependencies
  - Proxmox API — scripts use the Proxmox API and Terraform Proxmox provider. Token location: `terraform/terraform.tfvars`.
  - cloud-init — Terraform passes `cloud-init-master.yaml` and `cloud-init-worker.yaml` to VM templates; changes there affect initial users/ssh and early boot setup.
  - Kubernetes tooling: `kubeadm`, `kubelet`, `kubectl` are installed by Ansible roles; container runtime is `containerd` and CNI is Calico.

- Quick troubleshooting pointers for automation
  - If nodes are NotReady: check `ansible` play output, then `systemctl status kubelet` and `journalctl -u kubelet` on the node.
  - For CNI issues: confirm Calico pods via `kubectl -n kube-system get pods -l k8s-app=calico-node` and that `/opt/cni/bin` contains CNI binaries.
  - For template/Proxmox issues: re-run `scripts/create-template.sh` and `scripts/setup-api-token.sh`, and double-check `terraform/terraform.tfvars` values.

- Where to make common changes (examples)
  - Change Pod CIDR: update `ansible/roles/node.kubernetes` + Calico manifest used in `ansible/roles/node.cni`.
  - Change Kubernetes version: check Ansible role variables under `ansible/roles/node.kubernetes` and `ansible/roles/node.containerd/defaults`.
  - Change Proxmox/Terraform settings: `terraform/main.tf` and `terraform/terraform.tfvars`.

If anything here is incomplete or you want additional details (CI commands, exact kubeadm flags used, or examples of playbook task names), tell me which area to expand and I will update this file.
