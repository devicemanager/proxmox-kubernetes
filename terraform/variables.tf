# Proxmox connection variables
variable "proxmox_host" {
  description = "Proxmox host IP or hostname"
  type        = string
  default     = "192.168.20.40"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-5"
}

# Authentication method 1: Username/Password
variable "proxmox_user" {
  description = "Proxmox user (e.g., root@pam)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
  default     = ""
}

# Authentication method 2: API Token
variable "proxmox_api_token" {
  description = "Proxmox API token (format: user@realm!tokenid=token-secret)"
  type        = string
  sensitive   = true
  default     = ""
}

# Template and VM configuration
variable "template_id" {
  description = "Template VM ID"
  type        = number
  default     = 9000
}

variable "console_password" {
  description = "Console password for local VM access"
  type        = string
  sensitive   = true
}

variable "vm_network" {
  description = "Network configuration for VMs"
  type = object({
    subnet      = string
    gateway     = string
    dns_servers = string
  })
  default = {
    subnet      = "192.168.20"
    gateway     = "192.168.20.1"
    dns_servers = "192.168.20.1,1.1.1.1"
  }
}

variable "master_vm" {
  description = "Master node configuration"
  type = object({
    vmid        = number
    name        = string
    cores       = number
    memory      = number
    disk_size   = number
    ip_suffix   = number
  })
  default = {
    vmid        = 100
    name        = "k8s-master"
    cores       = 2
    memory      = 4096
    disk_size   = 32
    ip_suffix   = 51
  }
}

variable "worker_vm" {
  description = "Worker node configuration"
  type = object({
    vmid        = number
    name        = string
    cores       = number
    memory      = number
    disk_size   = number
    ip_suffix   = number
  })
  default = {
    vmid        = 101
    name        = "k8s-worker01"
    cores       = 2
    memory      = 4096
    disk_size   = 32
    ip_suffix   = 52
  }
}

