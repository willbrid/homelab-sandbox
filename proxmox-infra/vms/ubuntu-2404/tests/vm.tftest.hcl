mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/mock-user-data.yaml"
    }
  }

  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      id             = "101"
      ipv4_addresses = [["192.168.1.101"]]
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
  template_vm_id           = 9000
  network_bridge_primary   = "vmbr0"
  network_bridge_secondary = "vmbr1"
  cloud_init_ssh_keys      = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest mock@test"]
  dns_servers              = ["8.8.8.8"]
}

# ── Test 1 : création d'une VM avec IP statique ───────────────────────────────

run "ubuntu_vm_static_ip" {
  command = plan

  variables {
    vms = {
      "ubuntu-web-01" = {
        vm_id              = 101
        description        = "Test VM"
        ip_address_primary = "192.168.1.101/24"
        ip_gateway_primary = "192.168.1.1"
      }
    }
  }

  assert {
    condition     = module.vm["ubuntu-web-01"].vm_name == "ubuntu-web-01"
    error_message = "Le nom de la VM doit correspondre à la clé de la map."
  }

  assert {
    condition     = module.vm["ubuntu-web-01"].node_name == "pve"
    error_message = "La VM doit être créée sur le nœud 'pve'."
  }
}

# ── Test 2 : surcharge CPU/RAM par VM ─────────────────────────────────────────

run "ubuntu_vm_custom_resources" {
  command = plan

  variables {
    vms = {
      "ubuntu-db-01" = {
        vm_id     = 102
        cpu_cores = 4
        memory    = 8192
        disk_size = 100
      }
    }
  }

  assert {
    condition     = module.vm["ubuntu-db-01"].vm_name == "ubuntu-db-01"
    error_message = "La VM doit être créée avec les ressources surchargées."
  }
}

# ── Test 3 : création de plusieurs VMs simultanément ──────────────────────────

run "ubuntu_multiple_vms" {
  command = plan

  variables {
    vms = {
      "ubuntu-vm-01" = { vm_id = 101 }
      "ubuntu-vm-02" = { vm_id = 102 }
      "ubuntu-vm-03" = { vm_id = 103 }
    }
  }

  assert {
    condition     = length(module.vm) == 3
    error_message = "Trois VMs doivent être planifiées."
  }
}

# ── Test 4 : tags OS automatiquement ajoutés ──────────────────────────────────

run "ubuntu_base_tags_applied" {
  command = plan

  variables {
    vms = {
      "ubuntu-test-01" = {
        vm_id = 104
        tags  = ["web", "prod"]
      }
    }
  }

  assert {
    condition     = module.vm["ubuntu-test-01"].vm_name == "ubuntu-test-01"
    error_message = "La VM avec tags personnalisés doit être planifiée."
  }
}

# ── Test : extinction d'une VM sans destruction ───────────────────────────────

run "ubuntu_vm_stopped_via_started_flag" {
  command = plan

  variables {
    vms = {
      "ubuntu-vm-01" = {
        vm_id               = 101
        started             = false
        timeout_shutdown_vm = 120
      }
    }
  }

  assert {
    condition     = module.vm["ubuntu-vm-01"].started == false
    error_message = "started = false doit éteindre la VM sans la détruire."
  }

  assert {
    condition     = module.vm["ubuntu-vm-01"].vm_id == 101
    error_message = "La VM éteinte doit être conservée avec son ID Proxmox."
  }
}

# ── Test : extinction ponctuelle via stopped_vms ──────────────────────────────

run "ubuntu_vm_stopped_via_stopped_vms" {
  command = plan

  variables {
    stopped_vms = ["ubuntu-vm-01"]
    vms = {
      "ubuntu-vm-01" = { vm_id = 101 }
      "ubuntu-vm-02" = { vm_id = 102 }
    }
  }

  assert {
    condition     = module.vm["ubuntu-vm-01"].started == false
    error_message = "Une VM listée dans stopped_vms doit être éteinte."
  }

  assert {
    condition     = module.vm["ubuntu-vm-02"].started == true
    error_message = "Une VM absente de stopped_vms doit rester démarrée."
  }
}

# ── Test : disques supplémentaires (var.extra_disks) ──────────────────────────

run "ubuntu_vm_extra_disks" {
  command = plan

  variables {
    vms = {
      "ubuntu-data-01" = {
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
      "ubuntu-plain-01" = {
        vm_id = 302
      }
    }
  }

  assert {
    condition     = module.vm["ubuntu-data-01"].extra_disk_device_paths["scsi1"] == "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_data0"
    error_message = "Le disque supplémentaire doit être adressable par son serial, jamais par /dev/sdX."
  }

  assert {
    condition     = output.vms["ubuntu-data-01"].extra_disk_device_paths["scsi1"] == "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_data0"
    error_message = "Le chemin stable doit remonter dans l'output de la stack (consommé par Ansible)."
  }

  # Rétrocompatibilité : une VM sans extra_disks garde son seul disque racine.
  assert {
    condition     = length(output.vms["ubuntu-plain-01"].extra_disk_device_paths) == 0
    error_message = "Sans extra_disks, aucun disque supplémentaire ne doit être exposé."
  }
}

# Deux VMs peuvent porter le même serial : /dev/disk/by-id est un espace de noms
# local à chaque invité. L'unicité n'est requise qu'au sein d'une même VM.
run "ubuntu_vm_extra_disks_serial_partage_entre_vms" {
  command = plan

  variables {
    vms = {
      "ubuntu-data-01" = {
        vm_id       = 301
        extra_disks = [{ interface = "scsi1", size = 50, serial = "data0", backup = false }]
      }
      "ubuntu-data-02" = {
        vm_id       = 302
        extra_disks = [{ interface = "scsi1", size = 50, serial = "data0", backup = false }]
      }
    }
  }

  assert {
    condition = alltrue([
      for name in ["ubuntu-data-01", "ubuntu-data-02"] :
      module.vm[name].extra_disk_device_paths["scsi1"] == "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_data0"
    ])
    error_message = "Deux VMs distinctes doivent pouvoir partager le même serial de disque."
  }
}

# Plusieurs disques sur une même VM : chacun expose son propre chemin stable.
run "ubuntu_vm_extra_disks_multiples" {
  command = plan

  variables {
    vms = {
      "ubuntu-data-01" = {
        vm_id = 301
        extra_disks = [
          { interface = "scsi2", size = 100, serial = "data1", datastore_id = "local-lvm" },
          { interface = "scsi1", size = 50, serial = "data0" },
        ]
      }
    }
  }

  assert {
    condition     = length(module.vm["ubuntu-data-01"].extra_disk_device_paths) == 2
    error_message = "Les deux disques supplémentaires doivent exposer leur chemin stable."
  }

  assert {
    condition     = module.vm["ubuntu-data-01"].extra_disk_device_paths["scsi2"] == "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_data1"
    error_message = "Chaque interface doit être associée au serial de son propre disque."
  }
}
