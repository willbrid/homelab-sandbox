resource "proxmox_virtual_environment_vm" "vm" {
  vm_id     = var.vm_id
  name      = var.name
  node_name = var.node
  clone {
    vm_id = var.template_id
    full  = true
  }

  cpu    { cores = var.cores }
  memory { dedicated = var.memory }

  efi_disk {
    datastore_id = var.storage_vm
    type         = "4m"
  }

  disk {
    datastore_id = var.storage_vm
    interface    = "virtio0"
    size         = var.disk_size
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    datastore_id = var.storage_vm
    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }
}