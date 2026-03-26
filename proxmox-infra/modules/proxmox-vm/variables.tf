variable "vm_id" { 
  type = number
}

variable "template_id" { 
  type        = number
  description = "template id"
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

variable "name" { 
  type        = string 
  description = "template name"
}

variable "node" { 
  type        = string
  description = "vm node name"
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

variable "ip_address" { 
  type        = string 
  description = "vm ip address"
}

variable "gateway" { 
  type        = string 
  description = "vm gateway"
}