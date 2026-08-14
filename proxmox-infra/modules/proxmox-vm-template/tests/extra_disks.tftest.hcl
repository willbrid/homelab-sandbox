# Tests du module proxmox-vm-template centrés sur var.extra_disks.
# Exécution : depuis proxmox-infra/modules/proxmox-vm-template, `tofu init && tofu test`.
# Aucun accès à Proxmox : le provider est simulé (mock_provider).

mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      id = "9002"
    }
  }
}

variables {
  node_name                = "pve"
  vm_id                    = 9002
  template_name            = "rocky-10-template"
  image_filename           = "Rocky-10-GenericCloud.qcow2"
  disk_storage_id          = "local-lvm"
  network_bridge_primary   = "vmbr0"
  network_bridge_secondary = "vmbr1"
  cloud_init_user          = "rocky"
}

run "aucun_disque_supplementaire_par_defaut" {
  command = plan

  assert {
    condition     = length(proxmox_virtual_environment_vm.template.disk) == 1
    error_message = "Par défaut le template ne doit porter que le disque racine scsi0."
  }

  assert {
    condition     = length(output.extra_disk_interfaces) == 0
    error_message = "Sans disque supplémentaire, aucune interface ne doit être exposée."
  }
}

run "disque_supplementaire_vierge_sur_scsi1" {
  command = plan

  variables {
    disk_format = "raw"
    extra_disks = [{
      interface = "scsi1"
      size      = 40
      serial    = "data0"
      backup    = false
    }]
  }

  assert {
    condition     = [for d in proxmox_virtual_environment_vm.template.disk : d.interface] == ["scsi0", "scsi1"]
    error_message = "Le disque supplémentaire doit suivre le disque racine, trié par interface."
  }

  # Le disque racine est importé depuis l'image cloud, le supplémentaire est vierge.
  assert {
    condition     = proxmox_virtual_environment_vm.template.disk[1].file_id == null
    error_message = "Un disque supplémentaire de template doit être vierge (aucun file_id)."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.template.disk[1].file_format == "raw"
    error_message = "file_format non renseigné doit retomber sur var.disk_format."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.template.disk[1].serial == "data0"
    error_message = "Le serial doit être propagé au disque du template."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.template.disk[1].backup == false
    error_message = "backup = false doit exclure le disque des sauvegardes."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.template.boot_order == tolist(["scsi0"])
    error_message = "Le boot_order doit rester limité au disque racine importé."
  }

  # Contrat vers les stacks : les clones héritent de ces interfaces.
  assert {
    condition     = output.extra_disk_interfaces == tolist(["scsi1"])
    error_message = "Les interfaces héritées par les clones doivent être exposées en output."
  }
}

run "file_format_explicite_prime_sur_disk_format" {
  command = plan

  variables {
    disk_format = "raw"
    extra_disks = [{ interface = "scsi1", size = 40, file_format = "qcow2" }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.template.disk[1].file_format == "qcow2"
    error_message = "Un file_format explicite doit primer sur var.disk_format."
  }
}

# ── Validations ───────────────────────────────────────────────────────────────

run "refus_scsi0" {
  command = plan

  variables {
    extra_disks = [{ interface = "scsi0", size = 40 }]
  }

  expect_failures = [var.extra_disks]
}

run "refus_interface_hors_bus_scsi" {
  command = plan

  variables {
    extra_disks = [{ interface = "virtio1", size = 40 }]
  }

  expect_failures = [var.extra_disks]
}

run "refus_interface_dupliquee" {
  command = plan

  variables {
    extra_disks = [
      { interface = "scsi1", size = 40 },
      { interface = "scsi1", size = 50 },
    ]
  }

  expect_failures = [var.extra_disks]
}

run "refus_serial_duplique" {
  command = plan

  variables {
    extra_disks = [
      { interface = "scsi1", size = 40, serial = "data0" },
      { interface = "scsi2", size = 50, serial = "data0" },
    ]
  }

  expect_failures = [var.extra_disks]
}

run "refus_taille_negative" {
  command = plan

  variables {
    extra_disks = [{ interface = "scsi1", size = -10 }]
  }

  expect_failures = [var.extra_disks]
}
