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

variable "extra_disks" {
  description = <<-EOT
    Disques supplémentaires attachés au template, en plus du disque racine scsi0
    importé depuis l'image cloud. Chaque entrée produit un disque VIERGE : ni
    partitionné, ni formaté, ni monté.

    ATTENTION — portée : tout clone du template hérite de ces disques. Ne les
    déclarer ici que si TOUTES les VMs issues du template doivent les porter ;
    pour un besoin propre à certaines VMs (disque OpenEBS des workers, par
    exemple), utiliser var.extra_disks du module proxmox-vm. Un disque déclaré
    ici doit être redéclaré à l'identique côté proxmox-vm — sinon le provider
    planifiera sa suppression sur le clone.

      interface   : scsi1 … scsi30 — scsi0 est réservé au disque racine importé.
                    Le bus est restreint à scsi : le provider relit les disques
                    triés par interface, et un bus qui trie avant « scsi0 »
                    (ide, sata) produirait un diff permanent au plan.
      size        : en Go. Agrandir se fait en place ; réduire impose de recréer.
      serial      : rend le disque adressable via
                    /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_<serial>
      file_format : null (défaut) = var.disk_format
      backup      : false exclut le disque des sauvegardes Proxmox/PBS
      replicate   : false exclut le disque de la réplication ZFS entre nœuds
  EOT
  type = list(object({
    interface    = string
    size         = number
    serial       = optional(string)
    datastore_id = optional(string) # null = var.disk_storage_id
    file_format  = optional(string) # null = var.disk_format
    discard      = optional(string, "on")
    ssd          = optional(bool, true)
    iothread     = optional(bool, true)
    backup       = optional(bool, true)
    replicate    = optional(bool, true)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for d in var.extra_disks : d.interface != "scsi0"])
    error_message = "scsi0 est réservé au disque racine importé depuis l'image cloud."
  }

  validation {
    condition     = alltrue([for d in var.extra_disks : can(regex("^scsi([1-9]|[12][0-9]|30)$", d.interface))])
    error_message = "interface doit être scsi1 … scsi30 : le bus scsi est le seul supporté ici (scsi_hardware = virtio-scsi-single)."
  }

  validation {
    condition     = length(distinct([for d in var.extra_disks : d.interface])) == length(var.extra_disks)
    error_message = "Deux disques supplémentaires ne peuvent pas partager la même interface."
  }

  validation {
    condition     = alltrue([for d in var.extra_disks : d.size > 0])
    error_message = "La taille d'un disque supplémentaire doit être strictement positive (en Go)."
  }

  validation {
    condition     = alltrue([for d in var.extra_disks : d.serial == null || can(regex("^[A-Za-z0-9._-]{1,20}$", d.serial))])
    error_message = "serial : 20 caractères maximum parmi [A-Za-z0-9._-] (limite QEMU)."
  }

  validation {
    condition = length(compact([for d in var.extra_disks : d.serial == null ? "" : d.serial])) == length(
      distinct(compact([for d in var.extra_disks : d.serial == null ? "" : d.serial]))
    )
    error_message = "Deux disques d'un même template ne peuvent pas partager le même serial : /dev/disk/by-id ne serait plus déterministe."
  }

  validation {
    condition     = alltrue([for d in var.extra_disks : contains(["on", "ignore"], d.discard)])
    error_message = "discard doit valoir 'on' ou 'ignore'."
  }

  validation {
    condition     = alltrue([for d in var.extra_disks : d.file_format == null || contains(["raw", "qcow2", "vmdk"], coalesce(d.file_format, "raw"))])
    error_message = "file_format doit être 'raw', 'qcow2', 'vmdk' ou null (= var.disk_format)."
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
