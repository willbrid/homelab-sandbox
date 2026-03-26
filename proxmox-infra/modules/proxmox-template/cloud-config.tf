data "local_file" "ssh_public_key" {
  filename = var.ssh_public_key
}

resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = var.storage_images
  node_name    = var.node

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ${var.name}
    timezone: ${var.timezone}
    users:
      - default
      - name: ${var.vm_user}
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(data.local_file.ssh_public_key.content)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    package_update: true
    packages:
      - qemu-guest-agent
      - net-tools
      - curl
    runcmd:
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
      - echo "done" > /tmp/cloud-config.done
    EOF

    file_name = "user-data-cloud-config.yaml"
  }
}