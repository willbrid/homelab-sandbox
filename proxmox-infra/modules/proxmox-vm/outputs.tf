output "vm_id" {
  description = "Identifiant Proxmox de la VM."
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "vm_name" {
  description = "Nom de la VM."
  value       = proxmox_virtual_environment_vm.vm.name
}

output "node_name" {
  description = "Nœud Proxmox hébergeant la VM."
  value       = proxmox_virtual_environment_vm.vm.node_name
}

output "started" {
  description = "État d'alimentation souhaité de la VM (false = éteinte mais conservée)."
  value       = proxmox_virtual_environment_vm.vm.started
}

output "ipv4_addresses" {
  description = "Adresses IPv4 reportées par qemu-guest-agent (disponibles après démarrage)."
  value       = proxmox_virtual_environment_vm.vm.ipv4_addresses
}
