terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.99.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.7.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_url
  username  = var.proxmox_username
  password  = var.proxmox_password
  insecure  = true
  ssh {
    agent   = true
  }
}