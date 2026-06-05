# ── Connexion Proxmox ─────────────────────────────────────────────────────────

variable "proxmox_endpoint" {
  description = "URL de l'API Proxmox VE (ex: https://192.168.1.10:8006)."
  type        = string
}

variable "proxmox_username" {
  description = "Utilisateur Proxmox au format user@realm."
  type        = string
}

variable "proxmox_password" {
  description = "Mot de passe du compte Proxmox."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure_tls" {
  description = "Désactive la vérification TLS (certificats auto-signés)."
  type        = bool
  default     = false
}

variable "proxmox_ssh_username" {
  description = "Utilisateur SSH sur le nœud Proxmox."
  type        = string
  default     = "root"
}

variable "proxmox_ssh_password" {
  description = "Mot de passe SSH du nœud Proxmox."
  type        = string
  sensitive   = true
  default     = ""
}

# ── Infrastructure commune ────────────────────────────────────────────────────

variable "default_node_name" {
  description = "Nœud Proxmox par défaut pour toutes les VMs (surchargeable par VM)."
  type        = string
}

variable "disk_storage_id" {
  description = "Stockage Proxmox pour les disques VM."
  type        = string
}

variable "template_vm_id" {
  description = "ID du template Rocky Linux 9 à cloner."
  type        = number
  default     = 9001
}

# ── Valeurs par défaut des VMs ────────────────────────────────────────────────

variable "default_cpu_cores" {
  description = "Nombre de vCPU par défaut."
  type        = number
  default     = 2
}

variable "default_memory" {
  description = "RAM par défaut en Mo."
  type        = number
  default     = 2048
}

variable "default_disk_size" {
  description = "Taille de disque par défaut en Go."
  type        = number
  default     = 30
}

# ── Réseau ────────────────────────────────────────────────────────────────────

variable "network_bridge_primary" {
  description = "Bridge de l'interface primaire."
  type        = string
  default     = "vmbr0"
}

variable "network_vlan_primary" {
  description = "VLAN de l'interface primaire. null = sans VLAN."
  type        = number
  default     = null
  nullable    = true
}

variable "network_bridge_secondary" {
  description = "Bridge de l'interface secondaire."
  type        = string
  default     = "vmbr1"
}

variable "network_vlan_secondary" {
  description = "VLAN de l'interface secondaire. null = sans VLAN."
  type        = number
  default     = null
  nullable    = true
}

variable "dns_servers" {
  description = "Serveurs DNS injectés via cloud-init."
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "dns_domain" {
  description = "Domaine de recherche DNS."
  type        = string
  default     = ""
}

# ── Cloud-init ────────────────────────────────────────────────────────────────

variable "cloud_init_ssh_keys" {
  description = "Clés SSH publiques autorisées."
  type        = list(string)
  default     = []
}

# ── Cloud-init paquets ────────────────────────────────────────────────────────

variable "cloud_init_package_update" {
  description = "Met à jour la liste des paquets au premier boot (dnf check-update). Recommandé : false."
  type        = bool
  default     = false
}

variable "cloud_init_package_upgrade" {
  description = "Met à jour les paquets installés au premier boot (dnf upgrade). Recommandé : false."
  type        = bool
  default     = false
}

variable "snippets_storage_id" {
  description = "Stockage Proxmox supportant les snippets (contenu user-data cloud-init)."
  type        = string
  default     = "local"
}

# ── Timeouts ──────────────────────────────────────────────────────────────────

variable "timeout_clone" {
  description = "Timeout du clonage en secondes."
  type        = number
  default     = 1800
}

variable "timeout_start_vm" {
  description = "Timeout du démarrage VM en secondes (inclut l'attente du guest agent)."
  type        = number
  default     = 1800
}

# ── Définition des VMs ────────────────────────────────────────────────────────

variable "vms" {
  description = <<-EOT
    Map des VMs Rocky Linux 9 à créer. La clé est le nom de la VM.
    Les champs optionnels héritent des valeurs par défaut du module.
  EOT
  type = map(object({
    vm_id                  = number
    node_name              = optional(string)
    description            = optional(string, "")
    tags                   = optional(list(string), [])
    cpu_cores              = optional(number)
    memory                 = optional(number)
    disk_size              = optional(number)
    ip_address_primary     = optional(string)
    ip_gateway_primary     = optional(string)
    ip_address_secondary   = optional(string)
    network_vlan_primary   = optional(number)
    network_vlan_secondary = optional(number)
    on_boot                = optional(bool, true)
    started                = optional(bool, true)
  }))
}
