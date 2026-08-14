# Tests du module proxmox-vm centrés sur var.extra_disks.
# Exécution : depuis proxmox-infra/modules/proxmox-vm, `tofu init && tofu test`.
# Aucun accès à Proxmox : le provider est simulé (mock_provider).

mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/mock-user-data.yaml"
    }
  }

  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      id = "401"
    }
  }
}

variables {
  node_name                = "pve"
  vm_id                    = 401
  vm_name                  = "mock-worker-01"
  template_vm_id           = 9002
  disk_storage_id          = "local-lvm"
  network_bridge_primary   = "vmbr0"
  network_bridge_secondary = "vmbr1"
  cloud_init_user          = "rocky"
}

# ── Rétrocompatibilité : sans extra_disks, un seul disque ─────────────────────

run "aucun_disque_supplementaire_par_defaut" {
  command = plan

  assert {
    condition     = length(proxmox_virtual_environment_vm.vm.disk) == 1
    error_message = "Par défaut la VM ne doit porter que le disque racine scsi0."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.vm.disk).interface == "scsi0"
    error_message = "Le disque unique doit rester scsi0."
  }

  assert {
    condition     = length(output.extra_disk_device_paths) == 0
    error_message = "Sans disque supplémentaire, aucun chemin /dev/disk/by-id ne doit être exposé."
  }
}

# ── Cas nominal : le disque OpenEBS des workers ──────────────────────────────

run "disque_openebs_attache_sur_scsi1" {
  command = plan

  variables {
    extra_disks = [{
      interface = "scsi1"
      size      = 100
      serial    = "openebs0"
      backup    = false
    }]
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.vm.disk) == 2
    error_message = "La VM doit porter le disque racine et le disque supplémentaire."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vm.disk[1].interface == "scsi1"
    error_message = "Le disque supplémentaire doit être attaché sur scsi1, après scsi0."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vm.disk[1].size == 100
    error_message = "Le disque supplémentaire doit faire 100 Go."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vm.disk[1].serial == "openebs0"
    error_message = "Le serial doit être propagé : il conditionne le chemin /dev/disk/by-id."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vm.disk[1].backup == false
    error_message = "backup = false doit exclure le disque des sauvegardes Proxmox/PBS."
  }

  # Aucun file_id : le disque est alloué vierge, il n'est pas cloné d'une image.
  assert {
    condition     = proxmox_virtual_environment_vm.vm.disk[1].file_id == null
    error_message = "Un disque supplémentaire doit être vierge (aucun file_id)."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vm.disk[1].datastore_id == "local-lvm"
    error_message = "datastore_id non renseigné doit retomber sur var.disk_storage_id."
  }

  # NB : file_format n'est pas vérifié ici. L'attribut est Optional+Computed côté
  # provider — non renseigné, il est calculé d'après le stockage cible, et le mock
  # lui affecte une valeur arbitraire. C'est précisément le comportement recherché :
  # raw sur LVM/ZFS, qcow2 sur un stockage répertoire, sans diff permanent.

  assert {
    condition     = output.extra_disk_device_paths["scsi1"] == "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_openebs0"
    error_message = "Le chemin stable exposé doit dériver du serial du disque."
  }

  # Le disque supplémentaire étant vierge, il ne doit pas entrer dans le boot.
  assert {
    condition     = proxmox_virtual_environment_vm.vm.boot_order == tolist(["scsi0"])
    error_message = "Le boot_order doit rester limité au disque racine."
  }
}

# ── Plusieurs disques : ordre des blocs et valeurs par défaut ─────────────────

run "plusieurs_disques_ordonnes_par_interface" {
  command = plan

  variables {
    extra_disks = [
      # Volontairement déclarés à l'envers : la map interne les réordonne.
      { interface = "scsi2", size = 50, serial = "openebs1", datastore_id = "ceph-pool" },
      { interface = "scsi1", size = 100, serial = "openebs0" },
    ]
  }

  assert {
    condition     = [for d in proxmox_virtual_environment_vm.vm.disk : d.interface] == ["scsi0", "scsi1", "scsi2"]
    error_message = "Les disques doivent être générés triés par interface, comme le provider les relit."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vm.disk[2].datastore_id == "ceph-pool"
    error_message = "Un datastore_id explicite doit primer sur var.disk_storage_id."
  }

  assert {
    condition = alltrue([
      for d in slice(proxmox_virtual_environment_vm.vm.disk, 1, 3) :
      d.discard == "on" && d.ssd && d.iothread && d.backup && d.replicate
    ])
    error_message = "Les valeurs par défaut (discard/ssd/iothread/backup/replicate) doivent s'appliquer."
  }

  assert {
    condition     = length(output.extra_disk_device_paths) == 2
    error_message = "Chaque disque pourvu d'un serial doit exposer son chemin stable."
  }
}

run "disque_sans_serial_absent_des_chemins_stables" {
  command = plan

  variables {
    extra_disks = [{ interface = "scsi1", size = 20 }]
  }

  assert {
    condition     = length(output.extra_disk_device_paths) == 0
    error_message = "Un disque sans serial n'a pas de chemin déterministe : il ne doit pas être exposé."
  }
}

# ── Validations ───────────────────────────────────────────────────────────────

run "refus_scsi0" {
  command = plan

  variables {
    extra_disks = [{ interface = "scsi0", size = 50 }]
  }

  expect_failures = [var.extra_disks]
}

run "refus_interface_hors_bus_scsi" {
  command = plan

  variables {
    extra_disks = [{ interface = "sata0", size = 50 }]
  }

  expect_failures = [var.extra_disks]
}

run "refus_interface_dupliquee" {
  command = plan

  variables {
    extra_disks = [
      { interface = "scsi1", size = 50 },
      { interface = "scsi1", size = 60 },
    ]
  }

  expect_failures = [var.extra_disks]
}

run "refus_serial_duplique" {
  command = plan

  variables {
    extra_disks = [
      { interface = "scsi1", size = 50, serial = "openebs0" },
      { interface = "scsi2", size = 60, serial = "openebs0" },
    ]
  }

  expect_failures = [var.extra_disks]
}

run "refus_serial_trop_long" {
  command = plan

  variables {
    extra_disks = [{ interface = "scsi1", size = 50, serial = "openebs-disk-beaucoup-trop-long" }]
  }

  expect_failures = [var.extra_disks]
}

run "refus_taille_nulle" {
  command = plan

  variables {
    extra_disks = [{ interface = "scsi1", size = 0 }]
  }

  expect_failures = [var.extra_disks]
}

run "refus_discard_invalide" {
  command = plan

  variables {
    extra_disks = [{ interface = "scsi1", size = 50, discard = "off" }]
  }

  expect_failures = [var.extra_disks]
}

run "refus_file_format_invalide" {
  command = plan

  variables {
    extra_disks = [{ interface = "scsi1", size = 50, file_format = "vhdx" }]
  }

  expect_failures = [var.extra_disks]
}
