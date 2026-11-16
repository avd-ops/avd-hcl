mock_provider "azurerm" {}

variables {
  managing_tenant_id     = "00000000-0000-0000-0000-000000000010"
  target_subscription_id = "00000000-0000-0000-0000-000000000020"
  authorizations = [
    {
      principal_id           = "00000000-0000-0000-0000-000000000030"
      principal_display_name = "contoso-lab-admins"
      # Built-in Contributor role definition ID (public Azure constant)
      role_definition_id = "b24988ac-6180-42a0-ab88-20f7382dd24c"
    },
    {
      principal_id           = "00000000-0000-0000-0000-000000000031"
      principal_display_name = "contoso-lighthouse-cleanup"
      # Managed Services Registration Assignment Delete Role (public Azure constant)
      role_definition_id = "91c1777a-f3dc-4fae-b103-61d183457e46"
    },
  ]
}

run "lighthouse_delegation_plans" {
  command = plan

  assert {
    condition     = azurerm_lighthouse_definition.this.managing_tenant_id == "00000000-0000-0000-0000-000000000010"
    error_message = "Expected managing_tenant_id to match input."
  }

  assert {
    condition     = azurerm_lighthouse_definition.this.scope == "/subscriptions/00000000-0000-0000-0000-000000000020"
    error_message = "Expected Lighthouse definition scope to target the secondary subscription."
  }

  assert {
    condition     = length(azurerm_lighthouse_definition.this.authorization) == 2
    error_message = "Expected two Lighthouse authorization blocks."
  }
}
