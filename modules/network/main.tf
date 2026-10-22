# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/network; see CREDITS.md and NOTICE.
# Changes: no App Service integration subnet or SQL and web zones (no management app to host),
# subnets opt out of default outbound access, and the NAT gateway public IP follows
# availability_zones (avd-landing-zone lesson 0001) instead of always taking zones 1-3.

locals {
  private_dns_zones = {
    file  = "privatelink.file.core.windows.net"
    vault = "privatelink.vaultcore.azure.net"
    blob  = "privatelink.blob.core.windows.net"
  }
}

resource "azurerm_virtual_network" "avd" {
  name                = "vnet-${var.prefix}-avd"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "session_hosts" {
  name                            = "snet-session-hosts"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.avd.name
  address_prefixes                = [var.subnets.session_hosts]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.avd.name
  address_prefixes                  = [var.subnets.private_endpoints]
  private_endpoint_network_policies = "Enabled"
  default_outbound_access_enabled   = false
}

# Inbound stays closed: no rule allows it. The outbound rules name the flows the hosts need, but
# they don't restrict anything on their own, because the default AllowInternetOutBound rule still
# applies. Locking egress down to the AVD required URLs is the hub firewall's job, or comes with
# hardening in a later phase.
resource "azurerm_network_security_group" "session_hosts" {
  name                = "nsg-${var.prefix}-session-hosts"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-avd-service"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "WindowsVirtualDesktop"
  }

  security_rule {
    name                       = "allow-azure-cloud"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "allow-kms"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1688"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-${var.prefix}-private-endpoints"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-vnet-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "445"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
}

resource "azurerm_subnet_network_security_group_association" "session_hosts" {
  subnet_id                 = azurerm_subnet.session_hosts.id
  network_security_group_id = azurerm_network_security_group.session_hosts.id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = var.create_private_dns_zones ? local.private_dns_zones : {}
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each            = azurerm_private_dns_zone.this
  name                = "link-${azurerm_virtual_network.avd.name}"
  private_dns_zone_id = each.value.id
  virtual_network_id  = azurerm_virtual_network.avd.id
  tags                = var.tags
}

resource "azurerm_virtual_network_peering" "to_hub" {
  count                     = var.hub_vnet_id == null ? 0 : 1
  name                      = "peer-to-hub"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.avd.name
  remote_virtual_network_id = var.hub_vnet_id
  allow_forwarded_traffic   = true
  use_remote_gateways       = var.use_remote_gateways
}

# The subnets have no default outbound access, so session hosts need an explicit path out:
# this NAT gateway, or a default route to a hub firewall (egress_firewall_ip). One is required.
# The gateway itself stays regional; its IP is zone-redundant only where the region has zones,
# because a zoned IP fails in a region without them (avd-landing-zone lesson 0001).
resource "azurerm_public_ip" "nat" {
  count               = var.create_nat_gateway ? 1 : 0
  name                = "pip-${var.prefix}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = length(var.availability_zones) == 0 ? null : ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  count               = var.create_nat_gateway ? 1 : 0
  name                = "ng-${var.prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count                = var.create_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "session_hosts" {
  count          = var.create_nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.session_hosts.id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}

# Default route to a hub firewall, for when the hub handles egress instead of the NAT gateway.
# Peering alone doesn't send internet traffic through the hub.
resource "azurerm_route_table" "session_hosts" {
  count                         = var.egress_firewall_ip == null ? 0 : 1
  name                          = "rt-${var.prefix}-session-hosts"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.egress_firewall_ip
  }
}

resource "azurerm_subnet_route_table_association" "session_hosts" {
  count          = var.egress_firewall_ip == null ? 0 : 1
  subnet_id      = azurerm_subnet.session_hosts.id
  route_table_id = azurerm_route_table.session_hosts[0].id
}
