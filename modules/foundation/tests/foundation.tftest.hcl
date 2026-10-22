mock_provider "azurerm" {}

variables {
  location = "eastus2"
}

run "defaults" {
  command = plan

  assert {
    condition     = length(azurerm_resource_group.this) == 5
    error_message = "Expected the five role resource groups by default."
  }

  assert {
    condition     = azurerm_resource_group.this["session_hosts"].tags["avd-kit-role"] == "session_hosts"
    error_message = "Each resource group should be tagged with its role."
  }
}

run "missing_role_is_rejected" {
  command = plan

  variables {
    resource_groups = {
      network = "rg-net"
    }
  }

  expect_failures = [var.resource_groups]
}
