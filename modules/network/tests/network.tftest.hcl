# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/network/tests; see CREDITS.md and NOTICE.

mock_provider "azurerm" {}

variables {
  prefix              = "test"
  location            = "eastus2"
  resource_group_name = "rg-test"
}

run "defaults" {
  command = plan

  assert {
    condition     = length(azurerm_private_dns_zone.this) == 3
    error_message = "Expected the file, vault and blob privatelink zones by default."
  }

  assert {
    condition     = length(azurerm_nat_gateway.this) == 1
    error_message = "Expected a NAT gateway by default."
  }

  assert {
    condition     = length(azurerm_virtual_network_peering.to_hub) == 0
    error_message = "No peering without hub_vnet_id."
  }

  assert {
    condition     = !azurerm_subnet.session_hosts.default_outbound_access_enabled
    error_message = "Session hosts must leave the network through the NAT gateway or a hub, not default outbound access."
  }
}

# avd-landing-zone lesson 0001: a zoned public IP fails in a region without zones.
run "no_zones_means_regional_nat_ip" {
  command = plan

  assert {
    condition     = azurerm_public_ip.nat[0].zones == null
    error_message = "With no availability zones the NAT gateway IP must have no zones."
  }
}

run "zones_make_the_nat_ip_zone_redundant" {
  command = plan

  variables {
    availability_zones = ["1", "2", "3"]
  }

  assert {
    condition     = toset(azurerm_public_ip.nat[0].zones) == toset(["1", "2", "3"])
    error_message = "With availability zones the NAT gateway IP should be zone-redundant."
  }
}

run "hub_owns_dns_and_egress" {
  command = plan

  variables {
    hub_vnet_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
    create_private_dns_zones = false
    create_nat_gateway       = false
    egress_firewall_ip       = "10.0.0.4"
    existing_private_dns_zone_ids = {
      file = "/zones/file"
    }
  }

  assert {
    condition     = length(azurerm_private_dns_zone.this) == 0 && length(azurerm_nat_gateway.this) == 0
    error_message = "Zones and NAT gateway should be skipped."
  }

  assert {
    condition     = one(azurerm_route_table.session_hosts[0].route).next_hop_in_ip_address == "10.0.0.4"
    error_message = "Without the NAT gateway, session hosts route to the hub firewall."
  }

  assert {
    condition     = output.private_dns_zone_ids["file"] == "/zones/file"
    error_message = "Existing zone IDs should pass through."
  }
}

run "remote_gateways_need_a_hub" {
  command = plan

  variables {
    use_remote_gateways = true
  }

  expect_failures = [var.use_remote_gateways]
}

run "no_way_out_is_rejected" {
  command = plan

  variables {
    create_nat_gateway = false
  }

  expect_failures = [var.create_nat_gateway]
}
