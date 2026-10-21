output "host_pool_id" {
  description = "Host pool ID."
  value       = azurerm_virtual_desktop_host_pool.this.id
}

output "host_pool_name" {
  description = "Host pool name."
  value       = azurerm_virtual_desktop_host_pool.this.name
}

output "app_group_id" {
  description = "Desktop application group ID."
  value       = azurerm_virtual_desktop_application_group.desktop.id
}

output "workspace_id" {
  description = "Workspace ID."
  value       = azurerm_virtual_desktop_workspace.this.id
}

output "registration_host_pool_id" {
  description = "Host pool ID, available once the registration token's expiry is set. Session hosts read the token from it ephemerally."
  value       = azapi_update_resource.registration.resource_id
}
