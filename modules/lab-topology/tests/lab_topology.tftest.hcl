mock_provider "azurerm" {}

variables {
  prefix              = "avdlz"
  budget_start_date   = "2026-11-01T00:00:00Z"
  budget_alert_emails = ["avd-alerts@contoso.com"]
  existing_subscription_ids = {
    "platform-connectivity" = "00000000-0000-0000-0000-000000000001"
    "platform-management"   = "00000000-0000-0000-0000-000000000002"
    "lz-avd-workload"       = "00000000-0000-0000-0000-000000000003"
    "sandbox-ci"            = "00000000-0000-0000-0000-000000000004"
  }
}

run "existing_subscriptions_and_budgets" {
  command = plan

  assert {
    condition     = length(azurerm_management_group_subscription_association.lab) == 4
    error_message = "Expected four Management Group subscription associations."
  }

  assert {
    condition     = length(azurerm_consumption_budget_subscription.lab) == 4
    error_message = "Expected four per-subscription monthly budgets."
  }

  assert {
    condition     = azurerm_management_group.platform_connectivity.display_name == "connectivity"
    error_message = "Expected connectivity Management Group under platform."
  }
}

run "mca_subscription_vending" {
  command = plan

  variables {
    vend_subscriptions        = true
    billing_scope_id          = "/providers/Microsoft.Billing/billingAccounts/00000000/billingProfiles/00000000/invoiceSections/00000000"
    existing_subscription_ids = {}
    ci_principal_id           = "00000000-0000-0000-0000-000000000099"
  }

  assert {
    condition     = length(azurerm_subscription.vended) == 4
    error_message = "Expected four vended subscriptions when vend_subscriptions is true."
  }

  assert {
    condition     = azurerm_subscription.vended["sandbox-ci"].workload == "DevTest"
    error_message = "Expected sandbox-ci to use DevTest workload."
  }

  assert {
    condition     = length(azurerm_role_assignment.ci_sandbox_contributor) == 1
    error_message = "Expected sandbox Contributor role assignment for ci_principal_id."
  }
}
