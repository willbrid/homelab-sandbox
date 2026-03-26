# --- VMs Ubuntu 24.04 ---
module "vm_ubuntu_server" {
  source           = "../modules/proxmox-vm"
  proxmox_url      = var.proxmox_url
  proxmox_username = var.proxmox_username
  proxmox_password = var.proxmox_password
  vm_id            = 100
  name             = "ubuntu24-server"
  template_id      = 9000
  node             = "pve"
  storage_vm       = "local-lvm"
  cores            = 2
  memory           = 2048
  disk_size        = "50"
  ip_address       = "192.168.1.240/24"
  gateway          = "192.168.1.1"
}

# --- VMs Rocky Linux 9 ---
module "vm_rocky9_server" {
  source           = "../modules/proxmox-vm"
  proxmox_url      = var.proxmox_url
  proxmox_username = var.proxmox_username
  proxmox_password = var.proxmox_password
  vm_id            = 200
  name             = "rocky9-server"
  template_id      = 9001
  node             = "pve"
  storage_vm       = "local-lvm"
  cores            = 2
  memory           = 2048
  disk_size        = "50"
  ip_address       = "192.168.1.241/24"
  gateway          = "192.168.1.1"
}

# --- VMs Rocky Linux 10 ---
module "vm_rocky10_server" {
  source           = "../modules/proxmox-vm"
  proxmox_url      = var.proxmox_url
  proxmox_username = var.proxmox_username
  proxmox_password = var.proxmox_password
  vm_id            = 300
  name             = "rocky10-server"
  template_id      = 9002
  node             = "pve"
  storage_vm       = "local-lvm"
  cores            = 2
  memory           = 2048
  disk_size        = "50"
  ip_address       = "192.168.1.242/24"
  gateway          = "192.168.1.1"
}