output "vms" {
  description = "Informations des VMs Rocky Linux 10 créées."
  value = {
    for name, vm in module.vm : name => {
      vm_id          = vm.vm_id
      vm_name        = vm.vm_name
      node_name      = vm.node_name
      started        = vm.started
      ipv4_addresses = vm.ipv4_addresses
      # Chemins /dev/disk/by-id des disques supplémentaires, à consommer côté
      # Ansible plutôt que /dev/sdX (ordre non garanti d'un reboot à l'autre).
      extra_disk_device_paths = vm.extra_disk_device_paths
    }
  }
}
