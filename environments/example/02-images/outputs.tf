output "gallery_name" {
  description = "Compute Gallery name for packer/avd-win11."
  value       = module.image_gallery.gallery_name
}

output "gallery_resource_group_name" {
  description = "Resource group holding the Compute Gallery."
  value       = azurerm_resource_group.images.name
}

output "build_resource_group_name" {
  description = "Resource group Packer builds temporary VMs in."
  value       = module.image_gallery.build_resource_group_name
}

output "image_definition_ids" {
  description = "Image definition resource IDs keyed by name."
  value       = module.image_gallery.image_definition_ids
}
