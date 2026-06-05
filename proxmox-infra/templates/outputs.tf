output "ubuntu_2404_template" {
  description = "Informations du template Ubuntu 24.04."
  value = {
    vm_id          = module.ubuntu_2404_template.vm_id
    template_name  = module.ubuntu_2404_template.template_name
    node_name      = module.ubuntu_2404_template.node_name
    cloud_image_id = module.ubuntu_2404_template.cloud_image_id
  }
}

output "rocky_linux_9_template" {
  description = "Informations du template Rocky Linux 9."
  value = {
    vm_id          = module.rocky_linux_9_template.vm_id
    template_name  = module.rocky_linux_9_template.template_name
    node_name      = module.rocky_linux_9_template.node_name
    cloud_image_id = module.rocky_linux_9_template.cloud_image_id
  }
}

output "rocky_linux_10_template" {
  description = "Informations du template Rocky Linux 10."
  value = {
    vm_id          = module.rocky_linux_10_template.vm_id
    template_name  = module.rocky_linux_10_template.template_name
    node_name      = module.rocky_linux_10_template.node_name
    cloud_image_id = module.rocky_linux_10_template.cloud_image_id
  }
}
