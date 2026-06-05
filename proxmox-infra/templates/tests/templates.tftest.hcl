# Tests natifs OpenTofu pour le module proxmox-vm-template.
# Exécution : tofu test (depuis le répertoire proxmox-infra/)
#
# mock_provider simule le provider bpg/proxmox sans aucune connexion réelle.
# Les ressources retournent des valeurs par défaut réalistes.

mock_provider "proxmox" {
  # Seuls les attributs calculés (computed) peuvent figurer dans defaults.
  # Les champs configurés dans la ressource (node_name, etc.) sont exclus.
  mock_resource "proxmox_download_file" {
    defaults = {
      id = "local:iso/mock-cloud-image.img"
    }
  }

  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      id = "9000"
    }
  }
}

# ── Variables communes ────────────────────────────────────────────────────────

variables {
  proxmox_endpoint         = "https://192.168.1.10:8006"
  proxmox_username         = "terraform@pam"
  proxmox_password         = "mock-password"
  proxmox_insecure_tls     = true
  proxmox_ssh_username     = "root"
  proxmox_ssh_password     = "mock-password"
  node_name                = "pve"
  disk_storage_id          = "local-lvm"
  image_storage_id         = "local"
  network_bridge_primary   = "vmbr0"
  network_bridge_secondary = "vmbr1"
  cloud_init_user          = "ansible"
  cloud_init_ssh_keys      = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest mock@test"]
  cpu_cores                = 2
  cpu_type                 = "x86-64-v2-AES"
  memory                   = 2048
}

# ── Test 1 : Ubuntu 24.04 ─────────────────────────────────────────────────────

run "ubuntu_2404_template_plan" {
  command = plan

  variables {
    ubuntu_2404_vm_id    = 9000
    ubuntu_2404_disk_size = 20
  }

  assert {
    condition     = module.ubuntu_2404_template.template_name == "ubuntu-2404-template"
    error_message = "Le nom du template Ubuntu 24.04 doit être 'ubuntu-2404-template'."
  }

  assert {
    condition     = module.ubuntu_2404_template.vm_id == 9000
    error_message = "L'ID VM du template Ubuntu 24.04 doit être 9000."
  }

  assert {
    condition     = module.ubuntu_2404_template.node_name == "pve"
    error_message = "Le nœud Proxmox du template Ubuntu 24.04 doit être 'pve'."
  }
}

# ── Test 2 : Rocky Linux 9 ────────────────────────────────────────────────────

run "rocky_linux_9_template_plan" {
  command = plan

  variables {
    rocky_9_vm_id    = 9001
    rocky_9_disk_size = 20
  }

  assert {
    condition     = module.rocky_linux_9_template.template_name == "rocky-linux-9-template"
    error_message = "Le nom du template Rocky Linux 9 doit être 'rocky-linux-9-template'."
  }

  assert {
    condition     = module.rocky_linux_9_template.vm_id == 9001
    error_message = "L'ID VM du template Rocky Linux 9 doit être 9001."
  }

  assert {
    condition     = module.rocky_linux_9_template.node_name == "pve"
    error_message = "Le nœud Proxmox du template Rocky Linux 9 doit être 'pve'."
  }
}

# ── Test 3 : Rocky Linux 10 ───────────────────────────────────────────────────

run "rocky_linux_10_template_plan" {
  command = plan

  variables {
    rocky_10_vm_id    = 9002
    rocky_10_disk_size = 20
  }

  assert {
    condition     = module.rocky_linux_10_template.template_name == "rocky-linux-10-template"
    error_message = "Le nom du template Rocky Linux 10 doit être 'rocky-linux-10-template'."
  }

  assert {
    condition     = module.rocky_linux_10_template.vm_id == 9002
    error_message = "L'ID VM du template Rocky Linux 10 doit être 9002."
  }

  assert {
    condition     = module.rocky_linux_10_template.node_name == "pve"
    error_message = "Le nœud Proxmox du template Rocky Linux 10 doit être 'pve'."
  }
}

# ── Test 4 : IDs uniques (pas de collision entre templates) ───────────────────

run "vm_ids_are_unique" {
  command = plan

  variables {
    ubuntu_2404_vm_id  = 9000
    rocky_9_vm_id      = 9001
    rocky_10_vm_id     = 9002
  }

  assert {
    condition = (
      module.ubuntu_2404_template.vm_id != module.rocky_linux_9_template.vm_id &&
      module.ubuntu_2404_template.vm_id != module.rocky_linux_10_template.vm_id &&
      module.rocky_linux_9_template.vm_id != module.rocky_linux_10_template.vm_id
    )
    error_message = "Les VM IDs des trois templates doivent être uniques."
  }
}

# ── Test 5 : VLAN optionnel sur les interfaces réseau ────────────────────────

run "vlan_tagging_optional" {
  command = plan

  variables {
    network_vlan_primary   = 10
    network_vlan_secondary = 20
  }

  assert {
    condition     = module.ubuntu_2404_template.template_name == "ubuntu-2404-template"
    error_message = "Le template doit être planifié correctement avec les VLANs configurés."
  }
}
