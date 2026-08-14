# ── Connexion Proxmox API ─────────────────────────────────────────────────────

variable "proxmox_endpoint" {
  description = "URL de l'API Proxmox VE (ex: https://192.168.1.10:8006)."
  type        = string
}

variable "proxmox_username" {
  description = "Utilisateur Proxmox au format user@realm (ex: terraform@pam)."
  type        = string
}

variable "proxmox_password" {
  description = "Mot de passe du compte Proxmox. Préférer une variable d'environnement PROXMOX_VE_PASSWORD."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure_tls" {
  description = "Désactive la vérification du certificat TLS (utile pour les certificats auto-signés)."
  type        = bool
  default     = false
}

variable "proxmox_ssh_username" {
  description = "Utilisateur SSH sur le nœud Proxmox (généralement 'root')."
  type        = string
  default     = "root"
}

variable "proxmox_ssh_password" {
  description = "Mot de passe SSH du nœud Proxmox. Préférer une clé SSH via l'agent."
  type        = string
  sensitive   = true
  default     = ""
}

# ── Infrastructure commune ────────────────────────────────────────────────────

variable "node_name" {
  description = "Nom du nœud Proxmox cible (ex: pve, node01)."
  type        = string
}

variable "disk_storage_id" {
  description = "Stockage Proxmox pour les disques VM (ex: local-lvm, ceph-pool, local)."
  type        = string
}

variable "image_storage_id" {
  description = "Stockage pour les images cloud téléchargées. Doit supporter le contenu 'iso'."
  type        = string
  default     = "local"
}

# ── Réseau ────────────────────────────────────────────────────────────────────

variable "network_bridge_primary" {
  description = "Bridge Linux pour l'interface réseau primaire (management/LAN)."
  type        = string
  default     = "vmbr0"
}

variable "network_vlan_primary" {
  description = "Tag VLAN de l'interface primaire. null = accès sans VLAN."
  type        = number
  default     = null
  nullable    = true
}

variable "network_bridge_secondary" {
  description = "Bridge Linux pour l'interface réseau secondaire (workload/data)."
  type        = string
  default     = "vmbr1"
}

variable "network_vlan_secondary" {
  description = "Tag VLAN de l'interface secondaire. null = accès sans VLAN."
  type        = number
  default     = null
  nullable    = true
}

variable "network_model" {
  description = "Modèle de carte réseau virtuelle pour tous les templates."
  type        = string
  default     = "virtio"
}

# ── Cloud-init global ─────────────────────────────────────────────────────────

variable "cloud_init_user" {
  description = "Utilisateur par défaut injecté via cloud-init dans tous les templates."
  type        = string
}

variable "cloud_init_ssh_keys" {
  description = "Clés SSH publiques autorisées pour l'utilisateur cloud-init."
  type        = list(string)
  default     = []
}

# ── CPU / Mémoire (partagés entre templates) ──────────────────────────────────

variable "cpu_cores" {
  description = "Nombre de vCPU pour les templates."
  type        = number
  default     = 2
}

variable "cpu_type" {
  description = "Type CPU Proxmox (x86-64-v2-AES recommandé pour la compatibilité live-migration)."
  type        = string
  default     = "x86-64-v2-AES"
}

variable "memory" {
  description = "RAM en Mo allouée aux templates."
  type        = number
  default     = 2048
}

variable "qemu_agent_enabled" {
  description = "Active qemu-guest-agent (présent dans les images cloud Ubuntu et Rocky par défaut)."
  type        = bool
  default     = true
}

# ── Disques supplémentaires des templates ─────────────────────────────────────
#
# Un disque déclaré ici est porté par le TEMPLATE : toute VM clonée en hérite, et
# doit le redéclarer à l'identique dans var.extra_disks du module proxmox-vm —
# sinon le provider planifiera sa suppression sur le clone. Pour un disque propre
# à certaines VMs seulement (disque OpenEBS des workers, par exemple), passer par
# le champ extra_disks de var.vms des stacks proxmox-infra/vms/*, pas par ici.
#
# Le contrat complet (attributs, valeurs par défaut, validations) est porté par
# var.extra_disks du module proxmox-vm-template : interface scsi1…scsi30, disque
# laissé VIERGE (ni partitionné, ni formaté, ni monté), serial ≤ 20 caractères
# rendant le disque adressable via /dev/disk/by-id, file_format null = var.disk_format.

variable "ubuntu_2404_extra_disks" {
  description = "Disques supplémentaires du template Ubuntu 24.04. Hérités par tous ses clones."
  type = list(object({
    interface    = string
    size         = number
    serial       = optional(string)
    datastore_id = optional(string)
    file_format  = optional(string)
    discard      = optional(string, "on")
    ssd          = optional(bool, true)
    iothread     = optional(bool, true)
    backup       = optional(bool, true)
    replicate    = optional(bool, true)
  }))
  default  = []
  nullable = false
}

variable "rocky_9_extra_disks" {
  description = "Disques supplémentaires du template Rocky Linux 9. Hérités par tous ses clones."
  type = list(object({
    interface    = string
    size         = number
    serial       = optional(string)
    datastore_id = optional(string)
    file_format  = optional(string)
    discard      = optional(string, "on")
    ssd          = optional(bool, true)
    iothread     = optional(bool, true)
    backup       = optional(bool, true)
    replicate    = optional(bool, true)
  }))
  default  = []
  nullable = false
}

variable "rocky_10_extra_disks" {
  description = "Disques supplémentaires du template Rocky Linux 10. Hérités par tous ses clones."
  type = list(object({
    interface    = string
    size         = number
    serial       = optional(string)
    datastore_id = optional(string)
    file_format  = optional(string)
    discard      = optional(string, "on")
    ssd          = optional(bool, true)
    iothread     = optional(bool, true)
    backup       = optional(bool, true)
    replicate    = optional(bool, true)
  }))
  default  = []
  nullable = false
}

# ── Ubuntu 24.04 ──────────────────────────────────────────────────────────────

variable "ubuntu_2404_vm_id" {
  description = "ID VM Proxmox pour le template Ubuntu 24.04."
  type        = number
  default     = 9000
}

variable "ubuntu_2404_disk_size" {
  description = "Taille du disque du template Ubuntu 24.04 en Go."
  type        = number
  default     = 20
}

# ── Rocky Linux 9 ─────────────────────────────────────────────────────────────

variable "rocky_9_vm_id" {
  description = "ID VM Proxmox pour le template Rocky Linux 9."
  type        = number
  default     = 9001
}

variable "rocky_9_disk_size" {
  description = "Taille du disque du template Rocky Linux 9 en Go."
  type        = number
  default     = 20
}

# ── Rocky Linux 10 ────────────────────────────────────────────────────────────

variable "rocky_10_vm_id" {
  description = "ID VM Proxmox pour le template Rocky Linux 10."
  type        = number
  default     = 9002
}

variable "rocky_10_disk_size" {
  description = "Taille du disque du template Rocky Linux 10 en Go."
  type        = number
  default     = 20
}
