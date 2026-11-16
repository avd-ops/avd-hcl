# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/network; see CREDITS.md and NOTICE.

output "vnet_id" {
  description = "AVD spoke VNet ID. Peer the hub back to this (the hub side is not managed here)."
  value       = local.vnet_id
}

output "vnet_name" {
  description = "AVD spoke VNet name."
  value       = local.vnet_name
}

output "subnet_ids" {
  description = "Subnet IDs keyed by role."
  value = {
    session_hosts     = local.use_existing_network ? var.existing_session_hosts_subnet_id : azurerm_subnet.session_hosts[0].id
    private_endpoints = local.use_existing_network ? var.existing_private_endpoints_subnet_id : azurerm_subnet.private_endpoints[0].id
  }
}

output "private_dns_zone_ids" {
  description = "privatelink zone IDs keyed by file, vault and blob."
  value = var.create_private_dns_zones ? {
    for k, z in azurerm_private_dns_zone.this : k => z.id
  } : var.existing_private_dns_zone_ids
}
