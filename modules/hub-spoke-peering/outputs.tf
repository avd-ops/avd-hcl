output "peering_ids" {
  description = "Map of spoke keys to hub-to-spoke VNet peering resource IDs."
  value       = { for k, v in azurerm_virtual_network_peering.hub_to_spoke : k => v.id }
}

output "private_dns_link_ids" {
  description = "Map of spoke/zone keys to Private DNS virtual network link resource IDs."
  value       = { for k, v in azurerm_private_dns_zone_virtual_network_link.spoke : k => v.id }
}
