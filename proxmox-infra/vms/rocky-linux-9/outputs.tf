output "vms" {
  description = "Informations des VMs Rocky Linux 9 créées."
  value = {
    for name, vm in module.vm : name => {
      vm_id          = vm.vm_id
      vm_name        = vm.vm_name
      node_name      = vm.node_name
      ipv4_addresses = vm.ipv4_addresses
    }
  }
}
