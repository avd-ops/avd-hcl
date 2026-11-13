# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

mock_provider "azurerm" {}

variables {
  prefix              = "test-hub"
  location            = "eastus2"
  resource_group_name = "rg-hub-test"
}

run "lab_profile_defaults" {
  command = plan

  assert {
    condition     = azurerm_firewall.this[0].sku_tier == "Basic"
    error_message = "Lab profile must default to Basic Firewall SKU to limit idle spend."
  }

  assert {
    condition     = length(azurerm_bastion_host.this) == 0 && length(azurerm_private_dns_resolver.this) == 0 && length(azurerm_virtual_network_gateway.this) == 0
    error_message = "Lab profile must keep Bastion, Private Resolver, and Gateway disabled by default."
  }

  assert {
    condition     = !azurerm_subnet.firewall.default_outbound_access_enabled && !azurerm_subnet.gateway.default_outbound_access_enabled
    error_message = "All hub subnets must disable default outbound access."
  }
}

run "enterprise_profile_and_usgov_dns" {
  command = plan

  variables {
    cloud       = "usgov"
    environment = "prod"
    profile     = "enterprise"
    location    = "usgovvirginia"
  }

  assert {
    condition     = azurerm_firewall.this[0].sku_tier == "Standard" && length(azurerm_public_ip.fw_data) == 2
    error_message = "Enterprise profile must use Standard Firewall with 2 data PIPs."
  }

  assert {
    condition     = length(azurerm_bastion_host.this) == 1 && length(azurerm_private_dns_resolver.this) == 1
    error_message = "Enterprise profile must enable Bastion and DNS Private Resolver."
  }

  assert {
    condition     = azurerm_private_dns_zone.central["avd"].name == "privatelink.wvd.azure.us"
    error_message = "usgov cloud must use privatelink.wvd.azure.us."
  }
}
