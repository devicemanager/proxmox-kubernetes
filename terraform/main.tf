terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.69.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.20.40:8006/"
  insecure = true
  api_token = var.proxmox_api_token
#  username = var.proxmox_user

  ssh {
    agent    = true
    username = "root"
  }
}




# Master node VM
resource "proxmox_virtual_environment_vm" "k8s-master" {
  name        = var.master_vm.name
  node_name   = var.proxmox_node
  vm_id       = var.master_vm.vmid
  description = "Kubernetes master node"

  clone {
    vm_id = var.template_id
  }

  cpu {
    cores = var.master_vm.cores
  }

  memory {
    dedicated = var.master_vm.memory
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    size         = var.master_vm.disk_size
    datastore_id = "local-zfs"
    interface    = "scsi0"
    cache        = "none"
    discard      = "on"
  }

  started = true

  initialization {
    datastore_id = "local-zfs"

    ip_config {
      ipv4 {
        address = "${var.vm_network.subnet}.${var.master_vm.ip_suffix}/24"
        gateway = var.vm_network.gateway
      }
    }

    user_account {
      username = "debian"
      password = var.console_password
      keys     = [file("~/.ssh/id_rsa.pub")]
    }

    dns {
      domain    = "device manager.org"
      servers   = [var.vm_network.gateway]
    }
  }
}

# Worker node VM
resource "proxmox_virtual_environment_vm" "k8s-worker" {
  name        = var.worker_vm.name
  node_name   = var.proxmox_node
  vm_id       = var.worker_vm.vmid
  description = "Kubernetes worker node"

  clone {
    vm_id = var.template_id
  }

  cpu {
    cores = var.worker_vm.cores
  }

  memory {
    dedicated = var.worker_vm.memory
  }

  disk {
    size         = var.worker_vm.disk_size
    datastore_id = "local-zfs"
    interface    = "scsi0"
    cache        = "none"
    discard      = "on"
  }

  initialization {
    datastore_id = "local-zfs"

    ip_config {
      ipv4 {
        address = "${var.vm_network.subnet}.${var.worker_vm.ip_suffix}/24"
        gateway = var.vm_network.gateway
      }
    }

    user_account {
      username = "debian"
      password = var.console_password
      keys     = [file("~/.ssh/id_rsa.pub")]
    }

    dns {
      domain    = "device manager.org"
      servers   = [var.vm_network.gateway]
    }
  }

  started = true
}

# Outputs
output "master_ip" {
  value = "${var.vm_network.subnet}.${var.master_vm.ip_suffix}"
}

output "worker_ip" {
  value = "${var.vm_network.subnet}.${var.worker_vm.ip_suffix}"
}

output "console_access" {
  value = "qm terminal ${var.master_vm.vmid} or ${var.worker_vm.vmid} (user: root/debian, pass: from console_password)"
}
