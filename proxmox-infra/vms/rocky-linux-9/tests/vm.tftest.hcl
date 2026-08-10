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
