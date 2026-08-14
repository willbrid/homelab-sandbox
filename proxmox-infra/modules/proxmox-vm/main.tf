locals {
  ipv4_primary    = var.ip_address_primary != null ? var.ip_address_primary : "dhcp"
  gateway_primary = var.ip_address_primary != null ? var.ip_gateway_primary : null

  # L'interface secondaire n'est configurée via cloud-init que si une IP est explicitement
  # fournie. Laisser null évite d'injecter une config DHCP sur un bridge sans serveur DHCP,
  # ce qui bloquerait cloud-init (≥5 min d'attente) et retarderait le guest agent.
  configure_secondary = var.ip_address_secondary != null
  ipv4_secondary      = var.ip_address_secondary != null ? var.ip_address_secondary : "dhcp"
}

# Fichier cloud-init user-data stocké comme snippet Proxmox.
# Contrôle les mises à jour de paquets et configure l'utilisateur avec les
# groupes adaptés à la famille d'OS (sudo pour Ubuntu, wheel pour Rocky/RHEL).
resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.snippets_storage_id
  node_name    = var.node_name

  source_raw {
    data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
      package_update  = var.cloud_init_package_update
      package_upgrade = var.cloud_init_package_upgrade
      cloud_init_user = var.cloud_init_user
      user_groups     = var.cloud_init_user_groups
      ssh_keys        = var.cloud_init_ssh_keys
      hostname        = var.vm_name
      fqdn            = var.dns_domain != "" ? "${var.vm_name}.${var.dns_domain}" : ""
    })
    file_name = "${var.vm_name}-user-data.yaml"
  }
}

# Snippet network-data (Netplan v2) : utilisé uniquement pour Rocky Linux.
# network_data_file_id est incompatible avec ip_config dans le bloc initialization.
resource "proxmox_virtual_environment_file" "network_data" {
  count        = var.configure_network_in_cloudinit ? 1 : 0
  content_type = "snippets"
  datastore_id = var.snippets_storage_id
  node_name    = var.node_name

  source_raw {
    data = templatefile("${path.module}/templates/network-data.yaml.tftpl", {
      network_interface_primary   = var.network_interface_primary
      network_interface_secondary = var.network_interface_secondary
      ip_address_primary          = var.ip_address_primary
      ip_gateway_primary          = var.ip_gateway_primary
      ip_address_secondary        = var.ip_address_secondary
      dns_servers                 = var.dns_servers
    })
    file_name = "${var.vm_name}-network-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.vm_name
  description = var.description
  node_name   = var.node_name
  vm_id       = var.vm_id
  tags        = var.tags
  on_boot     = var.on_boot
  started     = var.started

  clone {
    vm_id   = var.template_vm_id
    full    = true
    retries = 3
  }

  timeout_clone    = var.timeout_clone
  timeout_start_vm = var.timeout_start_vm

  # Extinction : quand `started` passe à false (ou lors d'un destroy sans
  # stop_on_destroy), le provider appelle l'API shutdown de Proxmox avec
  # forceStop=1 et timeout=timeout_shutdown_vm. Concrètement : demande ACPI/agent
  # à l'OS d'abord, arrêt forcé seulement si l'OS n'a pas rendu la main dans ce
  # délai. La VM et ses disques sont conservés.
  timeout_shutdown_vm = var.timeout_shutdown_vm
  timeout_stop_vm     = var.timeout_stop_vm
  stop_on_destroy     = var.stop_on_destroy

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

  disk {
    datastore_id = var.disk_storage_id
    interface    = "scsi0"
    size         = var.disk_size
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  # Disques supplémentaires, vierges (aucun file_id : Proxmox alloue un volume neuf).
  # La clé de la map étant l'interface, les blocs sont générés dans l'ordre
  # lexicographique — le même que celui appliqué par le provider à la relecture de
  # l'état, où les disques sont triés par interface. Les entrées restant toutes
  # postérieures à « scsi0 » (validation sur var.extra_disks), l'ordre config et
  # l'ordre état coïncident : pas de diff parasite au plan.
  dynamic "disk" {
    for_each = { for d in var.extra_disks : d.interface => d }
    content {
      datastore_id = coalesce(disk.value.datastore_id, var.disk_storage_id)
      interface    = disk.key
      size         = disk.value.size
      file_format  = disk.value.file_format
      serial       = disk.value.serial
      discard      = disk.value.discard
      ssd          = disk.value.ssd
      iothread     = disk.value.iothread
      backup       = disk.value.backup
      replicate    = disk.value.replicate
    }
  }

  network_device {
    bridge   = var.network_bridge_primary
    model    = var.network_model
    vlan_id  = var.network_vlan_primary
    firewall = false
  }

  network_device {
    bridge   = var.network_bridge_secondary
    model    = var.network_model
    vlan_id  = var.network_vlan_secondary
    firewall = false
  }

  initialization {
    datastore_id         = var.disk_storage_id
    user_data_file_id    = proxmox_virtual_environment_file.user_data.id
    # Rocky Linux : réseau géré par network_data_file_id (Netplan v2).
    # Ubuntu       : réseau géré par ip_config ci-dessous.
    # Les deux options sont mutuellement exclusives dans le provider BPG.
    network_data_file_id = one(proxmox_virtual_environment_file.network_data[*].id)
    upgrade              = var.cloud_init_package_upgrade

    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }

    dynamic "ip_config" {
      for_each = var.configure_network_in_cloudinit ? [] : [1]
      content {
        ipv4 {
          address = local.ipv4_primary
          gateway = local.gateway_primary
        }
      }
    }

    dynamic "ip_config" {
      for_each = (!var.configure_network_in_cloudinit && local.configure_secondary) ? [1] : []
      content {
        ipv4 {
          address = local.ipv4_secondary
        }
      }
    }
  }

  operating_system {
    type = var.os_type
  }

  scsi_hardware = "virtio-scsi-single"

  # Volontairement limité au disque racine : les disques de var.extra_disks sont
  # vierges, donc non amorçables. L'expliciter évite que le BIOS les sonde au
  # démarrage et allonge le boot.
  boot_order = ["scsi0"]

  depends_on = [
    proxmox_virtual_environment_file.user_data,
    proxmox_virtual_environment_file.network_data,
  ]
}

# L'arrêt gracieux n'est tenté par le provider que si le qemu-guest-agent est
# activé sur la VM ; sinon il bascule directement sur un arrêt brutal
# (équivalent d'une coupure d'alimentation) et timeout_shutdown_vm est ignoré.
check "graceful_shutdown_requires_agent" {
  assert {
    condition     = var.qemu_agent_enabled || var.started
    error_message = "VM ${var.vm_name} : qemu_agent_enabled = false, l'extinction sera brutale (arrêt forcé immédiat) et timeout_shutdown_vm ne sera pas appliqué."
  }
}
