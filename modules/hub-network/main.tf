# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
# Terraform port of avd-networking (decision 0014), emitting C31 (avd-networking-outputs/v1).

locals {
  fw_sku_tier    = coalesce(var.firewall_sku_tier, var.profile == "lab" ? "Basic" : "Standard")
  is_basic_fw    = local.fw_sku_tier == "Basic"
  fw_pip_count   = local.is_basic_fw ? 1 : coalesce(var.firewall_public_ip_count, var.profile == "lab" ? 1 : 2)
  use_resolver   = coalesce(var.deploy_private_resolver, var.profile == "enterprise")
  use_bastion    = coalesce(var.deploy_bastion, var.profile == "enterprise")
  zones          = length(var.availability_zones) > 0 ? var.availability_zones : null
  hub_vnet_name  = "vnet-${var.prefix}-${var.environment}"
  fw_name        = "afw-${var.prefix}-${var.environment}"
  fw_policy_name = "afwp-${var.prefix}-${var.environment}"
  bastion_name   = "bas-${var.prefix}-${var.environment}"
  gateway_name   = "vgw-${var.prefix}-${var.environment}"
  resolver_name  = "dnspr-${var.prefix}-${var.environment}"

  private_dns_zones = var.cloud == "usgov" ? {
    file      = "privatelink.file.core.usgovcloudapi.net"
    keyVault  = "privatelink.vaultcore.usgovcloudapi.net"
    avd       = "privatelink.wvd.azure.us"
    avdGlobal = "privatelink-global.wvd.azure.us"
    } : {
    file      = "privatelink.file.core.windows.net"
    keyVault  = "privatelink.vaultcore.azure.net"
    avd       = "privatelink.wvd.microsoft.com"
    avdGlobal = "privatelink-global.wvd.microsoft.com"
  }
}

resource "azurerm_virtual_network" "hub" {
  name                = local.hub_vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.hub_address_prefix]
  tags                = var.tags
}

resource "azurerm_subnet" "gateway" {
  name                            = "GatewaySubnet"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = [var.gateway_subnet_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "firewall" {
  name                            = "AzureFirewallSubnet"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = [var.firewall_subnet_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "firewall_mgmt" {
  count                           = var.deploy_firewall && local.is_basic_fw ? 1 : 0
  name                            = "AzureFirewallManagementSubnet"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = [var.firewall_management_subnet_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "bastion" {
  count                           = local.use_bastion ? 1 : 0
  name                            = "AzureBastionSubnet"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = [var.bastion_subnet_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "dns_inbound" {
  count                           = local.use_resolver ? 1 : 0
  name                            = "snet-dns-inbound"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = [var.dns_inbound_subnet_prefix]
  default_outbound_access_enabled = false

  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name = "Microsoft.Network/dnsResolvers"
    }
  }
}

resource "azurerm_subnet" "dns_outbound" {
  count                           = local.use_resolver ? 1 : 0
  name                            = "snet-dns-outbound"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = [var.dns_outbound_subnet_prefix]
  default_outbound_access_enabled = false

  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name = "Microsoft.Network/dnsResolvers"
    }
  }
}

resource "azurerm_public_ip" "fw_data" {
  count               = var.deploy_firewall ? local.fw_pip_count : 0
  name                = "${local.fw_name}-pip-${count.index + 1}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.zones
  tags                = var.tags
}

resource "azurerm_public_ip" "fw_mgmt" {
  count               = var.deploy_firewall && local.is_basic_fw ? 1 : 0
  name                = "${local.fw_name}-mgmt-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.zones
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  count               = var.deploy_firewall ? 1 : 0
  name                = local.fw_policy_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = local.fw_sku_tier
  tags                = var.tags

  dynamic "dns" {
    for_each = local.is_basic_fw ? [] : [1]
    content {
      proxy_enabled = true
    }
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "avd" {
  count              = var.deploy_firewall ? 1 : 0
  name               = "rcg-avd-baseline"
  firewall_policy_id = azurerm_firewall_policy.this[0].id
  priority           = 200

  network_rule_collection {
    name     = "rc-avd-network"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "allow-avd-control-plane"
      protocols             = ["TCP"]
      source_addresses      = var.spoke_address_spaces
      destination_addresses = ["WindowsVirtualDesktop", "AzureMonitor", "AzureActiveDirectory"]
      destination_ports     = ["443"]
    }

    rule {
      name                  = "allow-kms-activation"
      protocols             = ["TCP"]
      source_addresses      = var.spoke_address_spaces
      destination_addresses = ["*"]
      destination_ports     = ["1688"]
    }

    dynamic "rule" {
      for_each = var.enable_shortpath_public ? [1] : []
      content {
        name                  = "allow-rdp-shortpath-stun-turn"
        protocols             = ["UDP"]
        source_addresses      = var.spoke_address_spaces
        destination_addresses = ["*"]
        destination_ports     = ["3478"]
      }
    }
  }

  application_rule_collection {
    name     = "rc-avd-application"
    priority = 300
    action   = "Allow"

    rule {
      name             = "allow-avd-fqdn-tag"
      source_addresses = var.spoke_address_spaces
      destination_fqdn_tags = [
        "WindowsVirtualDesktop",
        "WindowsUpdate",
        "AzureBackup",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}

resource "azurerm_firewall" "this" {
  count               = var.deploy_firewall ? 1 : 0
  name                = local.fw_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = local.fw_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.this[0].id
  zones               = local.zones
  tags                = var.tags

  dynamic "ip_configuration" {
    for_each = azurerm_public_ip.fw_data
    content {
      name                 = "fw-ipconfig-${ip_configuration.key + 1}"
      subnet_id            = ip_configuration.key == 0 ? azurerm_subnet.firewall.id : null
      public_ip_address_id = ip_configuration.value.id
    }
  }

  dynamic "management_ip_configuration" {
    for_each = local.is_basic_fw ? [1] : []
    content {
      name                 = "fw-mgmt-ipconfig"
      subnet_id            = azurerm_subnet.firewall_mgmt[0].id
      public_ip_address_id = azurerm_public_ip.fw_mgmt[0].id
    }
  }

  depends_on = [azurerm_firewall_policy_rule_collection_group.avd]
}

resource "azurerm_private_dns_zone" "central" {
  for_each            = var.deploy_private_dns_zones ? local.private_dns_zones : {}
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each              = var.deploy_private_dns_zones ? local.private_dns_zones : {}
  name                  = "link-hub"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.central[each.key].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_resolver" "this" {
  count               = local.use_resolver ? 1 : 0
  name                = local.resolver_name
  location            = var.location
  resource_group_name = var.resource_group_name
  virtual_network_id  = azurerm_virtual_network.hub.id
  tags                = var.tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "this" {
  count                   = local.use_resolver ? 1 : 0
  name                    = "inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.this[0].id
  location                = var.location
  tags                    = var.tags

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.dns_inbound[0].id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "this" {
  count                   = local.use_resolver ? 1 : 0
  name                    = "outbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.this[0].id
  location                = var.location
  subnet_id               = azurerm_subnet.dns_outbound[0].id
  tags                    = var.tags
}

resource "azurerm_public_ip" "bastion" {
  count               = local.use_bastion ? 1 : 0
  name                = "${local.bastion_name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  count               = local.use_bastion ? 1 : 0
  name                = local.bastion_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tunneling_enabled   = true
  tags                = var.tags

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}

resource "azurerm_public_ip" "gateway" {
  count               = var.deploy_gateway ? 1 : 0
  name                = "${local.gateway_name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.zones
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "this" {
  count               = var.deploy_gateway ? 1 : 0
  name                = local.gateway_name
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = var.gateway_type
  vpn_type            = var.gateway_type == "Vpn" ? "RouteBased" : null
  sku                 = var.gateway_sku
  tags                = var.tags

  ip_configuration {
    name                 = "gw-ipconfig"
    subnet_id            = azurerm_subnet.gateway.id
    public_ip_address_id = azurerm_public_ip.gateway[0].id
  }
}
