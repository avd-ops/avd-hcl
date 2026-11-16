mock_provider "azurerm" {}

run "default_providers_register" {
  command = plan

  assert {
    condition     = length(azurerm_resource_provider_registration.this) == 8
    error_message = "Expected eight default Resource Provider registrations."
  }

  assert {
    condition     = contains(keys(azurerm_resource_provider_registration.this), "Microsoft.DesktopVirtualization")
    error_message = "Expected Microsoft.DesktopVirtualization in registered providers."
  }

  assert {
    condition     = contains(keys(azurerm_resource_provider_registration.this), "Microsoft.ManagedServices")
    error_message = "Expected Microsoft.ManagedServices for Azure Lighthouse support."
  }
}
