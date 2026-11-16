mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing"
    }
  }
}

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

run "existing_resource_groups_are_reused" {
  command = plan

  variables {
    existing_resource_group_names = {
      network = "rg-existing-net"
      storage = "rg-existing-storage"
    }
  }

  assert {
    condition     = length(azurerm_resource_group.this) == 3 && length(data.azurerm_resource_group.existing) == 2
    error_message = "Roles in existing_resource_group_names are looked up instead of created."
  }

  assert {
    condition     = output.resource_group_names["network"] == "rg-existing-net" && output.resource_group_ids["storage"] == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-existing"
    error_message = "Existing resource group names and IDs flow through outputs."
  }
}
