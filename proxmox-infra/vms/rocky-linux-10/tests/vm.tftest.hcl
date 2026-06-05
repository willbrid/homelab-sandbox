mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/mock-user-data.yaml"
    }
  }

  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      id             = "301"
      ipv4_addresses = [["192.168.1.301"]]
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
  template_vm_id           = 9002
  network_bridge_primary   = "vmbr0"
  network_bridge_secondary = "vmbr1"
  cloud_init_ssh_keys      = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest mock@test"]
  dns_servers              = ["8.8.8.8"]
}

run "rocky10_vm_static_ip" {
  command = plan

  variables {
    vms = {
      "rocky10-app-01" = {
        vm_id              = 301
        ip_address_primary = "192.168.1.301/24"
        ip_gateway_primary = "192.168.1.1"
      }
    }
  }

  assert {
    condition     = module.vm["rocky10-app-01"].vm_name == "rocky10-app-01"
    error_message = "Le nom de la VM Rocky Linux 10 doit correspondre à la clé."
  }

  assert {
    condition     = module.vm["rocky10-app-01"].node_name == "pve"
    error_message = "La VM doit être créée sur le nœud 'pve'."
  }
}

run "rocky10_vm_custom_resources" {
  command = plan

  variables {
    vms = {
      "rocky10-heavy-01" = {
        vm_id     = 302
        cpu_cores = 8
        memory    = 16384
        disk_size = 200
      }
    }
  }

  assert {
    condition     = module.vm["rocky10-heavy-01"].vm_name == "rocky10-heavy-01"
    error_message = "La VM avec ressources élevées doit être planifiée."
  }
}

run "rocky10_multiple_vms" {
  command = plan

  variables {
    vms = {
      "rocky10-vm-01" = { vm_id = 301 }
      "rocky10-vm-02" = { vm_id = 302 }
    }
  }

  assert {
    condition     = length(module.vm) == 2
    error_message = "Deux VMs Rocky Linux 10 doivent être planifiées."
  }
}
