mock_provider "azurerm" {}

variables {
  hub_resource_group_name = "rg-avdlz-hub"
  hub_vnet_name           = "vnet-avdlz-hub"
  spoke_vnets = {
    "lz-avd-workload" = {
      remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-avdlz-network/providers/Microsoft.Network/virtualNetworks/vnet-avdlz"
    }
  }
  private_dns_zones = {
    "privatelink-wvd" = {
      private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-avdlz-hub/providers/Microsoft.Network/privateDnsZones/privatelink.wvd.microsoft.com"
    }
  }
}

run "hub_to_spoke_and_dns_links_plan" {
  command = plan

  assert {
    condition     = length(azurerm_virtual_network_peering.hub_to_spoke) == 1
    error_message = "Expected one hub-to-spoke VNet peering."
  }

  assert {
    condition     = azurerm_virtual_network_peering.hub_to_spoke["lz-avd-workload"].name == "peer-hub-to-lz-avd-workload"
    error_message = "Expected peering name peer-hub-to-lz-avd-workload."
  }

  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.spoke) == 1
    error_message = "Expected one Private DNS zone link for the spoke VNet."
  }
}
