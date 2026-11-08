mock_provider "azurerm" {
  mock_resource "azurerm_monitor_action_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-test"
    }
  }
}

variables {
  prefix              = "test"
  name                = "log-test-avd"
  location            = "eastus2"
  resource_group_name = "rg-test"
}

run "avd_insights_rule" {
  command = plan

  assert {
    condition     = startswith(azurerm_monitor_data_collection_rule.avd_insights.name, "microsoft-avdi-")
    error_message = "AVD Insights only finds rules named microsoft-avdi-*."
  }

  assert {
    condition     = !azurerm_log_analytics_workspace.avd.local_authentication_enabled
    error_message = "The workspace accepts Entra ID authentication only."
  }

  assert {
    condition     = length(azurerm_monitor_action_group.avd) == 0 && length(azurerm_consumption_budget_subscription.avd) == 0
    error_message = "No action group or budget without alert emails and a budget amount."
  }
}

run "budget_and_action_group" {
  command = plan

  variables {
    subscription_id       = "/subscriptions/00000000-0000-0000-0000-000000000000"
    alert_email_addresses = ["ops@contoso.com"]
    monthly_budget_amount = 150
    budget_start_date     = "2026-10-01T00:00:00Z"
  }

  assert {
    condition     = azurerm_monitor_action_group.avd[0].name == "ag-test-avd" && azurerm_consumption_budget_subscription.avd[0].amount == 150
    error_message = "Action group and monthly budget are created when emails, amount and start date are given."
  }
}
