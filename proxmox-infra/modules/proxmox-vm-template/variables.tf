# ── Identité du template ──────────────────────────────────────────────────────

variable "node_name" {
  description = "Nom du nœud Proxmox cible."
  type        = string
}

variable "vm_id" {
  description = "Identifiant numérique de la VM (ex: 9000)."
  type        = number
}

variable "template_name" {
  description = "Nom du template dans Proxmox."
  type        = string
}

variable "description" {
  description = "Description affichée dans l'interface Proxmox."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Liste de tags associés au template."
  type        = list(string)
  default     = []
}

# ── Image cloud ───────────────────────────────────────────────────────────────

variable "image_filename" {
  description = "Nom du fichier image stocké dans Proxmox (ex: noble-server-cloudimg-amd64.img)."
  type        = string
}

variable "image_storage_id" {
  description = "Identifiant du stockage Proxmox pour les images ISO/cloud (doit supporter le type 'iso')."
  type        = string
  default     = "local"
}

# ── Disque VM ─────────────────────────────────────────────────────────────────

variable "disk_storage_id" {
  description = "Identifiant du stockage pour les disques VM (ex: local-lvm, ceph-pool)."
  type        = string
}

variable "disk_size" {
  description = "Taille du disque racine en Go."
  type        = number
  default     = 30
}

variable "disk_format" {
  description = "Format du disque VM. 'raw' pour LVM/ZFS, 'qcow2' pour les stockages répertoires."
  type        = string
  default     = "raw"

  validation {
    condition     = contains(["raw", "qcow2", "vmdk"], var.disk_format)
    error_message = "disk_format doit être 'raw', 'qcow2' ou 'vmdk'."
  }
}

# ── CPU ───────────────────────────────────────────────────────────────────────

variable "cpu_cores" {
  description = "Nombre de cœurs vCPU."
  type        = number
  default     = 2
}

variable "cpu_type" {
  description = "Type CPU Proxmox (ex: x86-64-v2-AES, host, kvm64)."
  type        = string
  default     = "x86-64-v2-AES"
}

# ── Mémoire ───────────────────────────────────────────────────────────────────

variable "memory" {
  description = "Mémoire RAM allouée en Mo."
  type        = number
  default     = 2048
}

# ── Réseau ────────────────────────────────────────────────────────────────────

variable "network_bridge_primary" {
  description = "Bridge Linux pour l'interface réseau primaire (ex: vmbr0)."
  type        = string
}

variable "network_vlan_primary" {
  description = "Tag VLAN pour l'interface primaire. null = pas de VLAN."
  type        = number
  default     = null
  nullable    = true
}

variable "network_bridge_secondary" {
  description = "Bridge Linux pour l'interface réseau secondaire (ex: vmbr1)."
  type        = string
}

variable "network_vlan_secondary" {
  description = "Tag VLAN pour l'interface secondaire. null = pas de VLAN."
  type        = number
  default     = null
  nullable    = true
}

variable "network_model" {
  description = "Modèle de carte réseau virtuelle."
  type        = string
  default     = "virtio"

  validation {
    condition     = contains(["virtio", "e1000", "rtl8139", "vmxnet3"], var.network_model)
    error_message = "network_model doit être 'virtio', 'e1000', 'rtl8139' ou 'vmxnet3'."
  }
}

# ── Cloud-init ────────────────────────────────────────────────────────────────

variable "cloud_init_user" {
  description = "Nom de l'utilisateur par défaut injecté via cloud-init."
  type        = string
}

variable "cloud_init_ssh_keys" {
  description = "Liste de clés SSH publiques autorisées pour l'utilisateur cloud-init."
  type        = list(string)
  default     = []
}

# ── Agent QEMU ────────────────────────────────────────────────────────────────

variable "qemu_agent_enabled" {
  description = "Active la communication via qemu-guest-agent."
  type        = bool
  default     = true
}

# ── Système d'exploitation ────────────────────────────────────────────────────

variable "os_type" {
  description = "Type d'OS pour Proxmox (l26 = Linux 2.6+, win10, etc.)."
  type        = string
  default     = "l26"
}
