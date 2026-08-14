locals {
  os = {
    cloud_init_user   = "rocky"
    cloud_init_groups = ["wheel", "users"]
    os_type           = "l26"
    base_tags         = ["rocky", "rocky-10", "rhel"]
    cpu_type = "x86-64-v3"
  }
}

module "vm" {
  source   = "../../proxmox-infra/modules/proxmox-vm"
  for_each = var.vms

  node_name      = each.value.node_name != null ? each.value.node_name : var.default_node_name
  vm_id          = each.value.vm_id
  vm_name        = each.key
  description    = each.value.description
  tags           = concat(local.os.base_tags, each.value.tags)
  on_boot        = each.value.on_boot
  started        = each.value.started && !contains(var.stopped_vms, each.key)
  template_vm_id = var.template_vm_id

  disk_storage_id = var.disk_storage_id
  disk_size       = coalesce(each.value.disk_size, var.default_disk_size)
  extra_disks     = each.value.extra_disks

  cpu_cores = coalesce(each.value.cpu_cores, var.default_cpu_cores)
  cpu_type  = local.os.cpu_type
  memory    = coalesce(each.value.memory, var.default_memory)

  network_bridge_primary   = var.network_bridge_primary
  network_vlan_primary     = each.value.network_vlan_primary != null ? each.value.network_vlan_primary : var.network_vlan_primary
  network_bridge_secondary = var.network_bridge_secondary
  network_vlan_secondary   = each.value.network_vlan_secondary != null ? each.value.network_vlan_secondary : var.network_vlan_secondary

  ip_address_primary   = each.value.ip_address_primary
  ip_gateway_primary   = each.value.ip_gateway_primary
  ip_address_secondary = each.value.ip_address_secondary

  dns_servers = var.dns_servers
  dns_domain  = var.dns_domain

  cloud_init_user        = local.os.cloud_init_user
  cloud_init_user_groups = local.os.cloud_init_groups
  cloud_init_ssh_keys    = var.cloud_init_ssh_keys
  cloud_init_package_update  = var.cloud_init_package_update
  cloud_init_package_upgrade = var.cloud_init_package_upgrade
  snippets_storage_id    = var.snippets_storage_id
  os_type                = local.os.os_type

  qemu_agent_enabled = true
  configure_network_in_cloudinit = false

  timeout_clone    = var.timeout_clone
  timeout_start_vm = var.timeout_start_vm

  timeout_shutdown_vm = coalesce(each.value.timeout_shutdown_vm, var.timeout_shutdown_vm)
  timeout_stop_vm     = var.timeout_stop_vm
  stop_on_destroy     = var.stop_on_destroy
}
