# node.locales Ansible Role

This role installs and configures system locales (en_US.UTF-8) and ensures SSH accepts locale environment variables.

## Tasks performed
- Installs `locales` package
- Configures `/etc/locale.gen` for en_US.UTF-8
- Runs `locale-gen`
- Sets locale environment variables in `/etc/profile.d/locale.sh`
- Ensures SSHD accepts locale settings
- Restarts SSHD

## Usage
Add to your playbook:

```yaml
- hosts: k8s_nodes
  become: true
  roles:
    - node.locales
```

## Idempotency
All tasks are idempotent and safe to rerun.
