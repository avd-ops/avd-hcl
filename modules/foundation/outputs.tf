# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/foundation; see CREDITS.md and NOTICE.

output "resource_group_names" {
  description = "Resource group names keyed by role."
  value       = { for k, rg in azurerm_resource_group.this : k => rg.name }
}

output "resource_group_ids" {
  description = "Resource group IDs keyed by role."
  value       = { for k, rg in azurerm_resource_group.this : k => rg.id }
}
