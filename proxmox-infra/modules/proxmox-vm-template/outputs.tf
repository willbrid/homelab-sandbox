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

output "cloud_image_id" {
  description = "Identifiant Proxmox du fichier image téléchargé (ex: local:iso/noble-server-cloudimg-amd64.img)."
  value       = proxmox_download_file.cloud_image.id
}
