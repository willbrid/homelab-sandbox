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
    hostname: ${var.vm_hostname}
    timezone: ${var.timezone}
    users:
      - default
      - name: ${var.vm_user}
        groups:
          - ${var.vm_user_group}
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

    file_name = "user-data-cloud-config-${var.name}.yaml"
  }
}

resource "proxmox_virtual_environment_file" "network_data_cloud_config" {
  content_type = "snippets"
  datastore_id = var.storage_images
  node_name    = var.node

  source_raw {
    data = <<-EOF
    #network-config
    network:
      version: 2
      ethernets:
        eth0:
          dhcp4: yes
        eth1:
          dhcp4: no
          addresses:
            - ${var.vm_additional_ip}
    EOF

    file_name = "network-data-cloud-config-${var.name}.yaml"
  }
}