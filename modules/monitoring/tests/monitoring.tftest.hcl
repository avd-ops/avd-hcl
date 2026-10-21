mock_provider "azurerm" {}

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
}
