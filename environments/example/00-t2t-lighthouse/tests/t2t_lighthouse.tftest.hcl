mock_provider "azurerm" {}

variables {
  target_tenant_id       = "00000000-0000-0000-0000-000000000020"
  target_subscription_id = "00000000-0000-0000-0000-000000000021"
  managing_tenant_id     = "00000000-0000-0000-0000-000000000010"
  authorizations = [
    {
      principal_id           = "00000000-0000-0000-0000-000000000030"
      principal_display_name = "contoso-lab-admins"
      role_definition_id     = "b24988ac-6180-42a0-ab88-20f7382dd24c"
    },
  ]
}

run "t2t_root_plans_cleanly" {
  command = plan

  assert {
    condition     = length(output.registered_providers) == 8
    error_message = "Expected eight Resource Provider registrations."
  }

  assert {
    condition     = var.managing_tenant_id == "00000000-0000-0000-0000-000000000010"
    error_message = "Expected managing_tenant_id to match primary tenant."
  }
}
