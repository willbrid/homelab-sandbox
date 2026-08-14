output "vm_id" {
  description = "Identifiant numérique du template Proxmox."
  value       = proxmox_virtual_environment_vm.template.vm_id
}

output "template_name" {
  description = "Nom du template Proxmox."
  value       = proxmox_virtual_environment_vm.template.name
}

output "node_name" {
  description = "Nœud Proxmox hébergeant le template."
  value       = proxmox_virtual_environment_vm.template.node_name
}

output "extra_disk_interfaces" {
  description = <<-EOT
    Interfaces des disques supplémentaires portés par le template, triées.
    Tout clone en hérite : le module proxmox-vm doit redéclarer ces mêmes
    interfaces dans var.extra_disks, sinon le provider planifiera leur
    suppression sur la VM clonée.
  EOT
  value       = sort([for d in var.extra_disks : d.interface])
}

output "cloud_image_id" {
  description = "Référence Proxmox du fichier image local (ex: local:iso/noble-server-cloudimg-amd64-agent.img)."
  value       = "${var.image_storage_id}:iso/${var.image_filename}"
}
