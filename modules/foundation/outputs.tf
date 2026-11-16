# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/foundation; see CREDITS.md and NOTICE.

output "resource_group_names" {
  description = "Resource group names keyed by role."
  value = {
    for k in keys(var.resource_groups) : k => contains(keys(var.existing_resource_group_names), k) ? data.azurerm_resource_group.existing[k].name : azurerm_resource_group.this[k].name
  }
}

output "resource_group_ids" {
  description = "Resource group IDs keyed by role."
  value = {
    for k in keys(var.resource_groups) : k => contains(keys(var.existing_resource_group_names), k) ? data.azurerm_resource_group.existing[k].id : azurerm_resource_group.this[k].id
  }
}
