resource "proxmox_virtual_environment_vm" "template" {
  vm_id       = var.vm_id
  name        = var.name
  description = var.description
  node_name   = var.node
  template    = true

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.storage_vm
    file_id      = proxmox_virtual_environment_download_file.image.id
    interface    = "virtio0"
    size         = var.disk_size
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # Cloud-Init drive
  initialization {
    datastore_id = var.storage_vm
    ip_config {
      ipv4 { address = "dhcp" }
    }
    
    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id
  }
}

resource "proxmox_virtual_environment_download_file" "image" {
  content_type = "iso"
  datastore_id = var.storage_images
  node_name    = var.node
  url          = var.image_path
  file_name    = var.image_filename
}