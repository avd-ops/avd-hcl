variable "hub_resource_group_name" {
  type        = string
  description = "Resource group name containing the hub VNet in platform-connectivity."
}

variable "hub_vnet_name" {
  type        = string
  description = "Hub VNet name in platform-connectivity."
}

variable "spoke_vnets" {
  type = map(object({
    remote_virtual_network_id = string
    allow_gateway_transit     = optional(bool, false)
    allow_forwarded_traffic   = optional(bool, true)
  }))
  description = "Map of spoke keys (for example, lz-avd-workload) to spoke VNet peering settings."
}

variable "private_dns_zones" {
  type = map(object({
    private_dns_zone_id  = string
    registration_enabled = optional(bool, false)
  }))
  description = "Optional map of central Private DNS zone keys to resource IDs in platform-connectivity to link to each spoke VNet."
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to Private DNS virtual network links."
  default     = {}
}
