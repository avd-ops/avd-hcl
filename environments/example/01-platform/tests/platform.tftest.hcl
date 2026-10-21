# Plan-only test with mocked providers: the whole platform wires up without a tenant.

mock_provider "azurerm" {
  mock_data "azurerm_subscription" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
    }
  }
  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
    }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.test"
    }
  }
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
    }
  }
  mock_resource "azurerm_monitor_data_collection_rule" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/dataCollectionRules/microsoft-avdi-test"
    }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    }
  }
  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest"
    }
  }
  mock_resource "azurerm_virtual_desktop_host_pool" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.DesktopVirtualization/hostPools/vdpool-test"
    }
  }
  mock_resource "azurerm_virtual_desktop_application_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.DesktopVirtualization/applicationGroups/vdag-test"
    }
  }
  mock_resource "azurerm_virtual_desktop_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.DesktopVirtualization/workspaces/vdws-test"
    }
  }
  mock_resource "azurerm_virtual_desktop_scaling_plan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.DesktopVirtualization/scalingPlans/vdscaling-test"
    }
  }
  mock_resource "azurerm_network_interface" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkInterfaces/nic-test"
    }
  }
  mock_resource "azurerm_windows_virtual_machine" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Compute/virtualMachines/vm-test"
    }
  }
}

mock_provider "azuread" {
  mock_data "azuread_service_principal" {
    defaults = {
      object_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}

mock_provider "azapi" {}
mock_provider "random" {}
mock_provider "time" {}

variables {
  tenant_id              = "00000000-0000-0000-0000-000000000001"
  subscription_id        = "00000000-0000-0000-0000-000000000000"
  location               = "northcentralus"
  prefix                 = "avd-test"
  user_group_object_ids  = ["00000000-0000-0000-0000-000000000004"]
  admin_group_object_ids = ["00000000-0000-0000-0000-000000000005"]
}

run "sandbox_defaults" {
  command = plan

  assert {
    condition     = output.session_host_names == ["avdsh-001"]
    error_message = "One host by default."
  }

  assert {
    condition     = module.fslogix.storage_account_name == "stavdtest${substr(sha1("00000000-0000-0000-0000-000000000000/northcentralus/avd-test"), 0, 6)}"
    error_message = "The storage name is the compact prefix plus a stable suffix."
  }

  assert {
    condition     = length(module.key_vault.key_vault_name) <= 24 && length(module.fslogix.storage_account_name) <= 24
    error_message = "Globally unique names must fit Azure's 24-character limit."
  }

  assert {
    condition     = azurerm_role_assignment.avd_power_on_off.scope == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "Autoscale needs Power On Off Contributor at subscription scope."
  }

  assert {
    condition     = azurerm_role_assignment.avd_power_on_off.principal_id == "00000000-0000-0000-0000-000000000003"
    error_message = "The AVD service principal is looked up when not given."
  }
}

run "given_service_principal_skips_the_lookup" {
  command = plan

  variables {
    avd_service_principal_object_id = "00000000-0000-0000-0000-000000000006"
    availability_zones              = ["1", "2", "3"]
  }

  assert {
    condition     = length(data.azuread_service_principal.avd) == 0
    error_message = "No directory lookup when the object ID is given."
  }

  assert {
    condition     = azurerm_role_assignment.avd_power_on_off.principal_id == "00000000-0000-0000-0000-000000000006"
    error_message = "The given object ID is used."
  }
}

run "no_user_group_is_rejected" {
  command = plan

  variables {
    user_group_object_ids = []
  }

  expect_failures = [var.user_group_object_ids]
}

run "bad_prefix_is_rejected" {
  command = plan

  variables {
    prefix = "AVD_Prod"
  }

  expect_failures = [var.prefix]
}
