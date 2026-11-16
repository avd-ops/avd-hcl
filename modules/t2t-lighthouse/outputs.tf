output "lighthouse_definition_id" {
  description = "Resource ID of the Azure Lighthouse registration definition."
  value       = azurerm_lighthouse_definition.this.id
}

output "lighthouse_assignment_id" {
  description = "Resource ID of the Azure Lighthouse registration assignment."
  value       = azurerm_lighthouse_assignment.this.id
}
