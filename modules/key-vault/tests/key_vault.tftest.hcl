mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    }
  }
}

mock_provider "azapi" {}

variables {
  name                       = "kv-test"
  location                   = "eastus2"
  resource_group_name        = "rg-test"
  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-private-endpoints"
  private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  local_admin_username       = "avdadmin"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
}

run "private_rbac_vault" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled && azurerm_key_vault.this.purge_protection_enabled
    error_message = "The vault must use RBAC and purge protection."
  }

  assert {
    condition     = !azurerm_key_vault.this.public_network_access_enabled
    error_message = "The vault must not be reachable from the internet."
  }

  assert {
    condition     = azapi_resource.local_admin_username.type == "Microsoft.KeyVault/vaults/secrets@2023-07-01"
    error_message = "Secrets go through ARM, so a runner outside the VNet can write them."
  }
}

run "double_hyphen_is_rejected" {
  command = plan

  variables {
    name = "kv-avd--dev"
  }

  expect_failures = [var.name]
}
