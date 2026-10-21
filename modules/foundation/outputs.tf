output "resource_group_names" {
  description = "Resource group names keyed by role."
  value       = { for k, rg in azurerm_resource_group.this : k => rg.name }
}

output "resource_group_ids" {
  description = "Resource group IDs keyed by role."
  value       = { for k, rg in azurerm_resource_group.this : k => rg.id }
}
