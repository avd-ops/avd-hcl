# Plan-only test with mocked providers: the whole platform wires up without a tenant.
# Mock providers can't open ephemeral resources yet, so these runs plan zero session hosts (which
# skips reading the registration token) and the real random provider makes the ephemeral
# password offline. modules/session-hosts/tests covers the hosts themselves.

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
  mock_resource "azurerm_monitor_action_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-test"
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

mock_provider "azapi" {
  mock_data "azapi_resource" {
    defaults = {
      output = {
        properties = {
          state = "Registered"
        }
      }
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Compute/virtualMachines/vm-test"
    }
  }
}

# The mock providers can't open ephemeral resources yet, so the run's secrets are overridden.

mock_provider "time" {}

# A real azapi provider for modules/run-secrets, whose ephemeral read a mock can't hold. With no
# session hosts the read is skipped, so this provider never calls Azure; the placeholder settings only
# let it start without a sign-in.
provider "azapi" {
  alias           = "secrets"
  subscription_id = "00000000-0000-0000-0000-000000000000"
  tenant_id       = "00000000-0000-0000-0000-000000000001"
  client_id       = "00000000-0000-0000-0000-000000000007"
  client_secret   = "placeholder-never-used"
  use_cli         = false
  use_msi         = false
  use_oidc        = false
}

variables {
  tenant_id              = "00000000-0000-0000-0000-000000000001"
  subscription_id        = "00000000-0000-0000-0000-000000000000"
  location               = "northcentralus"
  prefix                 = "avd-test"
  user_group_object_ids  = ["00000000-0000-0000-0000-000000000004"]
  admin_group_object_ids = ["00000000-0000-0000-0000-000000000005"]
  host_count             = 0
}

run "sandbox_defaults" {
  command = plan

  assert {
    condition     = output.session_host_names == []
    error_message = "No hosts were asked for."
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
    condition     = azurerm_role_assignment.avd_power_on_off[0].scope == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "Autoscale needs Power On Off Contributor at subscription scope."
  }

  assert {
    condition     = azurerm_role_assignment.avd_power_on_off[0].principal_id == "00000000-0000-0000-0000-000000000003"
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
    condition     = azurerm_role_assignment.avd_power_on_off[0].principal_id == "00000000-0000-0000-0000-000000000006"
    error_message = "The given object ID is used."
  }
}

run "second_environment_leaves_the_power_role_alone" {
  command = plan

  variables {
    grant_avd_power_role = false
  }

  assert {
    condition     = length(azurerm_role_assignment.avd_power_on_off) == 0
    error_message = "Only one environment per subscription owns the subscription-scope role."
  }
}

run "missing_encryption_at_host_feature_stops_the_plan" {
  command = plan

  override_data {
    target = data.azapi_resource.encryption_at_host_feature[0]
    values = {
      output = {
        properties = {
          state = "NotRegistered"
        }
      }
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "double_hyphen_prefix_is_rejected" {
  command = plan

  variables {
    prefix = "avd--dev"
  }

  expect_failures = [var.prefix]
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

run "personal_pool_and_budget" {
  command = plan

  variables {
    host_pool_type        = "Personal"
    host_generation       = "b"
    auto_shutdown_time    = "2000"
    alert_email_addresses = ["ops@contoso.com"]
    monthly_budget_amount = 200
    budget_start_date     = "2026-10-01T00:00:00Z"
  }

  assert {
    condition     = output.host_pool_name == "vdpool-avd-test"
    error_message = "Personal pool, generation, auto-shutdown and budget plan cleanly through the platform root."
  }
}
