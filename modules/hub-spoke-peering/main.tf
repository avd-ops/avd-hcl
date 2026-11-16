locals {
  dns_links = merge([
    for spoke_key, spoke in var.spoke_vnets : {
      for zone_name, zone in var.private_dns_zones :
      "${spoke_key}/${zone_name}" => {
        spoke_key            = spoke_key
        zone_key             = zone_name
        private_dns_zone_id  = zone.private_dns_zone_id
        virtual_network_id   = spoke.remote_virtual_network_id
        registration_enabled = zone.registration_enabled
      }
    }
  ]...)
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = var.spoke_vnets

  name                      = "peer-hub-to-${each.key}"
  resource_group_name       = var.hub_resource_group_name
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = each.value.remote_virtual_network_id
  allow_gateway_transit     = each.value.allow_gateway_transit
  allow_forwarded_traffic   = each.value.allow_forwarded_traffic
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each = local.dns_links

  name                 = "link-${each.value.spoke_key}"
  private_dns_zone_id  = each.value.private_dns_zone_id
  virtual_network_id   = each.value.virtual_network_id
  registration_enabled = each.value.registration_enabled
  tags                 = var.tags
}
