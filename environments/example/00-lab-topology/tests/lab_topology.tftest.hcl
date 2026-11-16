mock_provider "azurerm" {}

variables {
  tenant_id           = "00000000-0000-0000-0000-000000000000"
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  budget_start_date   = "2026-11-01T00:00:00Z"
  budget_alert_emails = ["avd-alerts@contoso.com"]
  existing_subscription_ids = {
    "platform-connectivity" = "00000000-0000-0000-0000-000000000001"
    "platform-management"   = "00000000-0000-0000-0000-000000000002"
    "lz-avd-workload"       = "00000000-0000-0000-0000-000000000003"
    "sandbox-ci"            = "00000000-0000-0000-0000-000000000004"
  }
}

run "root_plans_cleanly" {
  command = plan

  assert {
    condition     = length(output.management_group_ids) == 6
    error_message = "Expected six ALZ Management Group outputs."
  }

  assert {
    condition     = length(output.subscription_ids) == 4
    error_message = "Expected four active lab subscription outputs."
  }
}
