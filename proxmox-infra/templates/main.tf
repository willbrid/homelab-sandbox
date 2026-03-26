module "template_ubuntu2404" {
  source           = "../modules/proxmox-template"
  proxmox_url      = var.proxmox_url
  proxmox_username = var.proxmox_username
  proxmox_password = var.proxmox_password
  vm_id            = 9000
  vm_user          = "ubuntu"
  vm_user_group    = "sudo"
  name             = "tpl-ubuntu-2404"
  description      = "Ubuntu 24.04 LTS cloud-init template"
  image_path       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  image_filename   = "noble-server-cloudimg-amd64.qcow2.img"
  node             = "pve"
  storage_images   = "local"
  storage_vm       = "local-lvm"
  ssh_public_key   = var.ssh_public_key
  timezone         = "Europe/Paris"
}

module "template_rocky9" {
  source           = "../modules/proxmox-template"
  proxmox_url      = var.proxmox_url
  proxmox_username = var.proxmox_username
  proxmox_password = var.proxmox_password
  vm_id            = 9001
  vm_user          = "rocky"
  vm_user_group    = "wheel"
  name             = "tpl-rocky-9"
  description      = "Rocky Linux 9 cloud-init template"
  image_path       = "https://dl.rockylinux.org/pub/rocky/9.7/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  image_filename   = "rocky-9-genericcloud-base-latest.qcow2.img"
  node             = "pve"
  storage_images   = "local"
  storage_vm       = "local-lvm"
  ssh_public_key   = var.ssh_public_key
  timezone         = "Europe/Paris"
}

module "template_rocky10" {
  source           = "../modules/proxmox-template"
  proxmox_url      = var.proxmox_url
  proxmox_username = var.proxmox_username
  proxmox_password = var.proxmox_password
  vm_id            = 9002
  vm_user          = "rocky"
  vm_user_group    = "wheel"
  name             = "tpl-rocky-10"  
  image_path       = "https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
  image_filename   = "rocky-10-genericcloud-base-latest.qcow2.img"
  description      = "Rocky Linux 10 cloud-init template"
  node             = "pve"
  storage_images   = "local"
  storage_vm       = "local-lvm"
  ssh_public_key   = var.ssh_public_key
  timezone         = "Europe/Paris"
}