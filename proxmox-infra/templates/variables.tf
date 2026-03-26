variable "proxmox_url" {
  type        = string
  description = "proxmox API URL"
}

variable "proxmox_username" {
  type        = string
  description = "proxmox username"
  sensitive   = true
}

variable "proxmox_password" {
  type        = string
  description = "proxmox password"
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "path to the SSH public key or key contents"
}