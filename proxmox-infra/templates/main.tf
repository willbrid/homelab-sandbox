locals {
  # Ubuntu 24.04 LTS (Noble Numbat) — image pré-construite par build-proxmox-image.sh
  ubuntu_2404 = {
    vm_id           = var.ubuntu_2404_vm_id
    template_name   = "ubuntu-2404-template"
    description     = "Ubuntu 24.04 LTS (Noble Numbat) - Cloud Image"
    tags            = ["ubuntu", "ubuntu-24.04", "cloud-init", "template"]
    image_filename  = "noble-server-cloudimg-amd64-agent.img"
    disk_size       = var.ubuntu_2404_disk_size
    disk_format     = "raw"
    cloud_init_user = "ubuntu"
    os_type         = "l26"
  }

  # Rocky Linux 9 — image pré-construite par build-proxmox-image.sh
  rocky_linux_9 = {
    vm_id           = var.rocky_9_vm_id
    template_name   = "rocky-linux-9-template"
    description     = "Rocky Linux 9 - Generic Cloud Image"
    tags            = ["rocky", "rocky-9", "rhel", "cloud-init", "template"]
    image_filename  = "Rocky-9-GenericCloud-Base.latest.x86_64-agent.img"
    disk_size       = var.rocky_9_disk_size
    disk_format     = "raw"
    cloud_init_user = "rocky"
    os_type         = "l26"
  }

  # Rocky Linux 10 — image pré-construite par build-proxmox-image.sh
  rocky_linux_10 = {
    vm_id           = var.rocky_10_vm_id
    template_name   = "rocky-linux-10-template"
    description     = "Rocky Linux 10 - Generic Cloud Image"
    tags            = ["rocky", "rocky-10", "rhel", "cloud-init", "template"]
    image_filename  = "Rocky-10-GenericCloud-Base.latest.x86_64-agent.img"
    disk_size       = var.rocky_10_disk_size
    disk_format     = "raw"
    cloud_init_user = "rocky"
    os_type         = "l26"
  }
}

module "ubuntu_2404_template" {
  source = "../modules/proxmox-vm-template"

  node_name     = var.node_name
  vm_id         = local.ubuntu_2404.vm_id
  template_name = local.ubuntu_2404.template_name
  description   = local.ubuntu_2404.description
  tags          = local.ubuntu_2404.tags

  image_filename   = local.ubuntu_2404.image_filename
  image_storage_id = var.image_storage_id

  disk_storage_id = var.disk_storage_id
  disk_size       = local.ubuntu_2404.disk_size
  disk_format     = local.ubuntu_2404.disk_format

  cpu_cores          = var.cpu_cores
  cpu_type           = var.cpu_type
  memory             = var.memory
  qemu_agent_enabled = var.qemu_agent_enabled

  network_bridge_primary   = var.network_bridge_primary
  network_vlan_primary     = var.network_vlan_primary
  network_bridge_secondary = var.network_bridge_secondary
  network_vlan_secondary   = var.network_vlan_secondary
  network_model            = var.network_model

  cloud_init_user     = local.ubuntu_2404.cloud_init_user
  cloud_init_ssh_keys = var.cloud_init_ssh_keys
  os_type             = local.ubuntu_2404.os_type
}

module "rocky_linux_9_template" {
  source = "../modules/proxmox-vm-template"

  node_name     = var.node_name
  vm_id         = local.rocky_linux_9.vm_id
  template_name = local.rocky_linux_9.template_name
  description   = local.rocky_linux_9.description
  tags          = local.rocky_linux_9.tags

  image_filename   = local.rocky_linux_9.image_filename
  image_storage_id = var.image_storage_id

  disk_storage_id = var.disk_storage_id
  disk_size       = local.rocky_linux_9.disk_size
  disk_format     = local.rocky_linux_9.disk_format

  cpu_cores          = var.cpu_cores
  cpu_type           = var.cpu_type
  memory             = var.memory
  qemu_agent_enabled = var.qemu_agent_enabled

  network_bridge_primary   = var.network_bridge_primary
  network_vlan_primary     = var.network_vlan_primary
  network_bridge_secondary = var.network_bridge_secondary
  network_vlan_secondary   = var.network_vlan_secondary
  network_model            = var.network_model

  cloud_init_user     = local.rocky_linux_9.cloud_init_user
  cloud_init_ssh_keys = var.cloud_init_ssh_keys
  os_type             = local.rocky_linux_9.os_type
}

module "rocky_linux_10_template" {
  source = "../modules/proxmox-vm-template"

  node_name     = var.node_name
  vm_id         = local.rocky_linux_10.vm_id
  template_name = local.rocky_linux_10.template_name
  description   = local.rocky_linux_10.description
  tags          = local.rocky_linux_10.tags

  image_filename   = local.rocky_linux_10.image_filename
  image_storage_id = var.image_storage_id

  disk_storage_id = var.disk_storage_id
  disk_size       = local.rocky_linux_10.disk_size
  disk_format     = local.rocky_linux_10.disk_format

  cpu_cores          = var.cpu_cores
  cpu_type           = var.cpu_type
  memory             = var.memory
  qemu_agent_enabled = var.qemu_agent_enabled

  network_bridge_primary   = var.network_bridge_primary
  network_vlan_primary     = var.network_vlan_primary
  network_bridge_secondary = var.network_bridge_secondary
  network_vlan_secondary   = var.network_vlan_secondary
  network_model            = var.network_model

  cloud_init_user     = local.rocky_linux_10.cloud_init_user
  cloud_init_ssh_keys = var.cloud_init_ssh_keys
  os_type             = local.rocky_linux_10.os_type
}
