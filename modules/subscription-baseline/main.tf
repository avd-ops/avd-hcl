resource "azurerm_resource_provider_registration" "this" {
  for_each = toset(var.resource_providers)
  name     = each.value
}
