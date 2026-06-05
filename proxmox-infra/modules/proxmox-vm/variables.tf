# ── Identité de la VM ─────────────────────────────────────────────────────────

variable "node_name" {
  description = "Nœud Proxmox cible."
  type        = string
}

variable "vm_id" {
  description = "Identifiant numérique de la VM."
  type        = number
}

variable "vm_name" {
  description = "Nom de la VM (hostname visible dans Proxmox)."
  type        = string
}

variable "description" {
  description = "Description affichée dans l'interface Proxmox."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags associés à la VM."
  type        = list(string)
  default     = []
}

variable "on_boot" {
  description = "Démarre automatiquement la VM au boot du nœud Proxmox."
  type        = bool
  default     = true
}

variable "started" {
  description = "État de la VM après création (true = démarrée)."
  type        = bool
  default     = true
}

# ── Clonage depuis le template ────────────────────────────────────────────────

variable "template_vm_id" {
  description = "ID VM du template Proxmox à cloner."
  type        = number
}

# ── Disque ────────────────────────────────────────────────────────────────────

variable "disk_storage_id" {
  description = "Stockage Proxmox pour le disque cloné et le drive cloud-init."
  type        = string
}

variable "disk_size" {
  description = "Taille du disque racine en Go (doit être >= taille du template)."
  type        = number
  default     = 30
}

# ── CPU ───────────────────────────────────────────────────────────────────────

variable "cpu_cores" {
  description = "Nombre de vCPU."
  type        = number
  default     = 2
}

variable "cpu_type" {
  description = "Type CPU Proxmox."
  type        = string
  default     = "x86-64-v2-AES"
}

# ── Mémoire ───────────────────────────────────────────────────────────────────

variable "memory" {
  description = "RAM allouée en Mo."
  type        = number
  default     = 2048
}

# ── Réseau ────────────────────────────────────────────────────────────────────

variable "network_bridge_primary" {
  description = "Bridge de l'interface réseau primaire."
  type        = string
}

variable "network_vlan_primary" {
  description = "Tag VLAN de l'interface primaire. null = sans VLAN."
  type        = number
  default     = null
  nullable    = true
}

variable "network_bridge_secondary" {
  description = "Bridge de l'interface réseau secondaire."
  type        = string
}

variable "network_vlan_secondary" {
  description = "Tag VLAN de l'interface secondaire. null = sans VLAN."
  type        = number
  default     = null
  nullable    = true
}

variable "network_model" {
  description = "Modèle de carte réseau virtuelle."
  type        = string
  default     = "virtio"
}

# ── IP / Cloud-init réseau ────────────────────────────────────────────────────

variable "ip_address_primary" {
  description = "IP de l'interface primaire au format CIDR (ex: 192.168.1.10/24). null = DHCP."
  type        = string
  default     = null
  nullable    = true
}

variable "ip_gateway_primary" {
  description = "Passerelle par défaut pour l'interface primaire. Ignoré si ip_address_primary = null."
  type        = string
  default     = null
  nullable    = true
}

variable "ip_address_secondary" {
  description = <<-EOT
    IP de l'interface secondaire au format CIDR (ex: 192.168.2.10/24) ou "dhcp".
    null (défaut) = l'interface réseau secondaire existe mais n'est PAS configurée
    par cloud-init, évitant toute attente DHCP sur un bridge sans serveur.
  EOT
  type     = string
  default  = null
  nullable = true
}

variable "dns_servers" {
  description = "Liste des serveurs DNS injectés via cloud-init."
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "dns_domain" {
  description = "Domaine de recherche DNS."
  type        = string
  default     = ""
}

# ── Cloud-init utilisateur ────────────────────────────────────────────────────

variable "cloud_init_user" {
  description = "Utilisateur par défaut injecté via cloud-init."
  type        = string
}

variable "cloud_init_ssh_keys" {
  description = "Clés SSH publiques autorisées pour l'utilisateur cloud-init."
  type        = list(string)
  default     = []
}

variable "cloud_init_user_groups" {
  description = <<-EOT
    Groupes système de l'utilisateur cloud-init. Diffère selon la famille d'OS :
    - Ubuntu/Debian : ["sudo", "adm", "users"]
    - Rocky/RHEL    : ["wheel", "users"]
  EOT
  type        = list(string)
  default     = []
}

variable "cloud_init_package_update" {
  description = <<-EOT
    Active la mise à jour de la liste des paquets au premier boot (apt update / dnf check-update).
    Recommandé : false pour les templates et environnements contrôlés.
  EOT
  type    = bool
  default = false
}

variable "cloud_init_package_upgrade" {
  description = <<-EOT
    Active la mise à jour des paquets installés au premier boot (apt upgrade / dnf upgrade).
    Recommandé : false — ralentit significativement le premier boot et peut provoquer
    des timeouts du provider (jusqu'à 20 min sur Rocky Linux 10 avec SELinux relabeling).
  EOT
  type    = bool
  default = false
}

variable "snippets_storage_id" {
  description = "Stockage Proxmox supportant le contenu 'snippets' pour le fichier user-data cloud-init."
  type        = string
  default     = "local"
}

# ── Système ───────────────────────────────────────────────────────────────────

variable "qemu_agent_enabled" {
  description = "Active la communication avec qemu-guest-agent."
  type        = bool
  default     = true
}

variable "os_type" {
  description = "Type d'OS Proxmox (l26 = Linux 2.6+)."
  type        = string
  default     = "l26"
}

# ── Timeouts ──────────────────────────────────────────────────────────────────

variable "timeout_clone" {
  description = "Timeout du clonage du template en secondes. Augmenter pour les images lourdes."
  type        = number
  default     = 1800
}

variable "timeout_start_vm" {
  description = <<-EOT
    Timeout du démarrage en secondes. Le provider attend la réponse du
    qemu-guest-agent avant de considérer la VM comme créée. Augmenter pour
    les OS dont le premier boot (cloud-init, SELinux relabeling) est long.
  EOT
  type        = number
  default     = 1800
}
