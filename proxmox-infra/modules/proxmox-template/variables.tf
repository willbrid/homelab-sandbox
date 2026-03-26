variable "vm_id" { 
  type = number 
}

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

variable "vm_user" {
  type        = string
  description = "default user injected via cloud-init"
  default     = "tofu"
}

variable "name" { 
  type        = string 
  description = "template name"
}

variable "node" { 
  type        = string
  description = "vm node name"
}

variable "description" { 
  type        = string
  description = "temaplate description"
}

variable "image_path" { 
  type        = string
  description = "os image path"
}

variable "image_filename" { 
  type        = string
  description = "os image filename"
}

variable "storage_images" {
  type        = string
  description = "file-based storage for images and snippets"
  default     = "local"
}

variable "storage_vm" {
  type        = string
  description = "storage for vm disks"
  default     = "local-lvm"
}

variable "cores" { 
  type        = number
  default     = 2
  description = "cpu cores"
}

variable "memory" { 
  type        = number
  default     = 2048
  description = "memory size"
}

variable "disk_size" { 
  type        = string 
  default     = "20"
  description = "disk size"
}

variable "ssh_public_key" {
  type        = string
  description = "path to the SSH public key or key contents"
}

variable "timezone" {
  type        = string
  description = "timezone of VMs"
  default     = "Europe/Paris"
}