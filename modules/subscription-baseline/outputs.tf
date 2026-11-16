output "registered_providers" {
  description = "Map of registered Resource Provider namespaces to their resource IDs."
  value       = { for k, v in azurerm_resource_provider_registration.this : k => v.id }
}
