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

output "extra_disk_device_paths" {
  description = <<-EOT
    Chemin stable de chaque disque supplémentaire pourvu d'un serial, indexé par
    interface. À consommer côté Ansible / DiskPool plutôt que /dev/sdX, dont
    l'ordre n'est pas garanti d'un redémarrage à l'autre. Les disques sans serial
    ne sont pas listés : ils n'ont pas de chemin déterministe.
  EOT
  value = {
    for d in var.extra_disks : d.interface => "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_${d.serial}"
    if d.serial != null
  }
}

output "ipv4_addresses" {
  description = "Adresses IPv4 reportées par qemu-guest-agent (disponibles après démarrage)."
  value       = proxmox_virtual_environment_vm.vm.ipv4_addresses
}
