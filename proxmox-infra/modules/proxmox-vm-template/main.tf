resource "proxmox_virtual_environment_vm" "template" {
  name        = var.template_name
  description = var.description
  node_name   = var.node_name
  vm_id       = var.vm_id
  template    = true
  tags        = var.tags

  # L'agent suppose que qemu-guest-agent est présent dans l'image cloud.
  agent {
    enabled = var.qemu_agent_enabled
  }

  cpu {
    cores   = var.cpu_cores
    sockets = 1
    type    = var.cpu_type
  }

  memory {
    dedicated = var.memory
  }

  # Disque racine importé depuis l'image locale dans le stockage ISO Proxmox.
  disk {
    datastore_id = var.disk_storage_id
    file_id      = "${var.image_storage_id}:iso/${var.image_filename}"
    interface    = "scsi0"
    size         = var.disk_size
    file_format  = var.disk_format
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  # Disques supplémentaires, vierges (aucun file_id : Proxmox alloue un volume neuf).
  # La clé de la map étant l'interface, les blocs suivent l'ordre lexicographique,
  # celui-là même que le provider applique en relisant l'état — et toutes les
  # entrées trient après « scsi0 » (validation sur var.extra_disks). Config et état
  # coïncident donc : pas de diff parasite au plan.
  # Rappel : tout clone de ce template héritera de ces disques.
  dynamic "disk" {
    for_each = { for d in var.extra_disks : d.interface => d }
    content {
      datastore_id = coalesce(disk.value.datastore_id, var.disk_storage_id)
      interface    = disk.key
      size         = disk.value.size
      file_format  = coalesce(disk.value.file_format, var.disk_format)
      serial       = disk.value.serial
      discard      = disk.value.discard
      ssd          = disk.value.ssd
      iothread     = disk.value.iothread
      backup       = disk.value.backup
      replicate    = disk.value.replicate
    }
  }

  # Interface réseau primaire (management/LAN).
  network_device {
    bridge   = var.network_bridge_primary
    model    = var.network_model
    vlan_id  = var.network_vlan_primary
    firewall = false
  }

  # Interface réseau secondaire (workload/stockage/supervision).
  network_device {
    bridge   = var.network_bridge_secondary
    model    = var.network_model
    vlan_id  = var.network_vlan_secondary
    firewall = false
  }

  # Cloud-init : injection de la configuration réseau et utilisateur.
  # Deux blocs ip_config correspondent aux deux interfaces réseau.
  initialization {
    datastore_id = var.disk_storage_id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = var.cloud_init_user
      keys     = var.cloud_init_ssh_keys
    }
  }

  operating_system {
    type = var.os_type
  }

  # virtio-scsi-single est requis pour activer iothread par disque.
  scsi_hardware = "virtio-scsi-single"

  # Seul le disque racine est amorçable : les disques de var.extra_disks sont
  # vierges et n'ont pas à être sondés au démarrage.
  boot_order = ["scsi0"]

  # Sortie série requise par les images cloud Ubuntu et Rocky pour la console.
  serial_device {
    device = "socket"
  }

  vga {
    type = "serial0"
  }

}
