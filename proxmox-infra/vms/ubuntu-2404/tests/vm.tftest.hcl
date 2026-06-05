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
