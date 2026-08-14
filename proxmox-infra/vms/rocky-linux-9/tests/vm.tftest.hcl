mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/mock-user-data.yaml"
    }
  }

  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      id             = "201"
      ipv4_addresses = [["192.168.1.201"]]
    }
  }
}

variables {
  proxmox_endpoint         = "https://192.168.1.10:8006"
  proxmox_username         = "terraform@pam"
  proxmox_password         = "mock-password"
  proxmox_insecure_tls     = true
  proxmox_ssh_username     = "root"
  proxmox_ssh_password     = "mock-password"
  default_node_name        = "pve"
  disk_storage_id          = "local-lvm"
  template_vm_id           = 9001
  network_bridge_primary   = "vmbr0"
  network_bridge_secondary = "vmbr1"
  cloud_init_ssh_keys      = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest mock@test"]
  dns_servers              = ["8.8.8.8"]
}

run "rocky9_vm_static_ip" {
  command = plan

  variables {
    vms = {
      "rocky9-app-01" = {
        vm_id              = 201
        ip_address_primary = "192.168.1.201/24"
        ip_gateway_primary = "192.168.1.1"
      }
    }
  }

  assert {
    condition     = module.vm["rocky9-app-01"].vm_name == "rocky9-app-01"
    error_message = "Le nom de la VM Rocky Linux 9 doit correspondre à la clé."
  }

  assert {
    condition     = module.vm["rocky9-app-01"].node_name == "pve"
    error_message = "La VM doit être créée sur le nœud 'pve'."
  }
}

run "rocky9_vm_dhcp" {
  command = plan

  variables {
    vms = {
      "rocky9-dhcp-01" = {
        vm_id = 202
      }
    }
  }

  assert {
    condition     = module.vm["rocky9-dhcp-01"].vm_name == "rocky9-dhcp-01"
    error_message = "La VM en DHCP doit être planifiée correctement."
  }
}

run "rocky9_multiple_vms" {
  command = plan

  variables {
    vms = {
      "rocky9-vm-01" = { vm_id = 201 }
      "rocky9-vm-02" = { vm_id = 202 }
    }
  }

  assert {
    condition     = length(module.vm) == 2
    error_message = "Deux VMs Rocky Linux 9 doivent être planifiées."
  }
}

# ── Test : extinction d'une VM sans destruction ───────────────────────────────

run "rocky9_vm_stopped_via_started_flag" {
  command = plan

  variables {
    vms = {
      "rocky9-vm-01" = {
        vm_id               = 201
        started             = false
        timeout_shutdown_vm = 120
      }
    }
  }

  assert {
    condition     = module.vm["rocky9-vm-01"].started == false
    error_message = "started = false doit éteindre la VM sans la détruire."
  }

  assert {
    condition     = module.vm["rocky9-vm-01"].vm_id == 201
    error_message = "La VM éteinte doit être conservée avec son ID Proxmox."
  }
}

# ── Test : extinction ponctuelle via stopped_vms ──────────────────────────────

run "rocky9_vm_stopped_via_stopped_vms" {
  command = plan

  variables {
    stopped_vms = ["rocky9-vm-01"]
    vms = {
      "rocky9-vm-01" = { vm_id = 201 }
      "rocky9-vm-02" = { vm_id = 202 }
    }
  }

  assert {
    condition     = module.vm["rocky9-vm-01"].started == false
    error_message = "Une VM listée dans stopped_vms doit être éteinte."
  }

  assert {
    condition     = module.vm["rocky9-vm-02"].started == true
    error_message = "Une VM absente de stopped_vms doit rester démarrée."
  }
}

# ── Test : disques supplémentaires (var.extra_disks) ──────────────────────────

run "rocky9_vm_extra_disks" {
  command = plan

  variables {
    vms = {
      "rocky9-data-01" = {
        vm_id     = 301
        disk_size = 80
        # scsi1 vierge : ni partitionné, ni formaté, ni monté par le module.
        extra_disks = [{
          interface = "scsi1"
          size      = 50
          serial    = "data0"
          backup    = false
        }]
      }
      "rocky9-plain-01" = {
        vm_id = 302
      }
    }
  }

  assert {
    condition     = module.vm["rocky9-data-01"].extra_disk_device_paths["scsi1"] == "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_data0"
    error_message = "Le disque supplémentaire doit être adressable par son serial, jamais par /dev/sdX."
  }

  assert {
    condition     = output.vms["rocky9-data-01"].extra_disk_device_paths["scsi1"] == "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_data0"
    error_message = "Le chemin stable doit remonter dans l'output de la stack (consommé par Ansible)."
  }

  # Rétrocompatibilité : une VM sans extra_disks garde son seul disque racine.
  assert {
    condition     = length(output.vms["rocky9-plain-01"].extra_disk_device_paths) == 0
    error_message = "Sans extra_disks, aucun disque supplémentaire ne doit être exposé."
  }
}

# Deux VMs peuvent porter le même serial : /dev/disk/by-id est un espace de noms
# local à chaque invité. L'unicité n'est requise qu'au sein d'une même VM.
run "rocky9_vm_extra_disks_serial_partage_entre_vms" {
  command = plan

  variables {
    vms = {
      "rocky9-data-01" = {
        vm_id       = 301
        extra_disks = [{ interface = "scsi1", size = 50, serial = "data0", backup = false }]
      }
      "rocky9-data-02" = {
        vm_id       = 302
        extra_disks = [{ interface = "scsi1", size = 50, serial = "data0", backup = false }]
      }
    }
  }

  assert {
    condition = alltrue([
      for name in ["rocky9-data-01", "rocky9-data-02"] :
      module.vm[name].extra_disk_device_paths["scsi1"] == "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_data0"
    ])
    error_message = "Deux VMs distinctes doivent pouvoir partager le même serial de disque."
  }
}

# Plusieurs disques sur une même VM : chacun expose son propre chemin stable.
run "rocky9_vm_extra_disks_multiples" {
  command = plan

  variables {
    vms = {
      "rocky9-data-01" = {
        vm_id = 301
        extra_disks = [
          { interface = "scsi2", size = 100, serial = "data1", datastore_id = "local-lvm" },
          { interface = "scsi1", size = 50, serial = "data0" },
        ]
      }
    }
  }

  assert {
    condition     = length(module.vm["rocky9-data-01"].extra_disk_device_paths) == 2
    error_message = "Les deux disques supplémentaires doivent exposer leur chemin stable."
  }

  assert {
    condition     = module.vm["rocky9-data-01"].extra_disk_device_paths["scsi2"] == "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_data1"
    error_message = "Chaque interface doit être associée au serial de son propre disque."
  }
}
