# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

locals {
  fw_private_ip = var.deploy_firewall ? azurerm_firewall.this[0].ip_configuration[0].private_ip_address : ""
  dns_servers_out = local.use_resolver ? [
    azurerm_private_dns_resolver_inbound_endpoint.this[0].ip_configurations[0].private_ip_address
  ] : (var.deploy_firewall && !local.is_basic_fw ? [local.fw_private_ip] : [])
}

output "networking_outputs" {
  description = "C31 avd-networking-outputs/v1 contract object."
  value = {
    schema               = "avd-networking-outputs/v1"
    cloud                = var.cloud
    environment          = var.environment
    location             = var.location
    profile              = var.profile
    connectivityTopology = "hub-spoke"
    resourceGroup        = var.resource_group_name
    hubVnetResourceId    = azurerm_virtual_network.hub.id
    hubFirewallPrivateIp = local.fw_private_ip
    dnsServers           = local.dns_servers_out
    centralPrivateDnsZoneResourceIds = {
      file      = var.deploy_private_dns_zones ? azurerm_private_dns_zone.central["file"].id : ""
      keyVault  = var.deploy_private_dns_zones ? azurerm_private_dns_zone.central["keyVault"].id : ""
      avd       = var.deploy_private_dns_zones ? azurerm_private_dns_zone.central["avd"].id : ""
      avdGlobal = var.deploy_private_dns_zones ? azurerm_private_dns_zone.central["avdGlobal"].id : ""
    }
    bastionResourceId = local.use_bastion ? azurerm_bastion_host.this[0].id : ""
    gatewayResourceId = var.deploy_gateway ? azurerm_virtual_network_gateway.this[0].id : ""
  }
}
