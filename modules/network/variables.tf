# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/network; see CREDITS.md and NOTICE.

variable "prefix" {
  description = "Short naming prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the AVD virtual network."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "address_space" {
  description = "Address space for the AVD spoke VNet."
  type        = list(string)
  default     = ["10.50.0.0/20"]
}

variable "subnets" {
  description = "Subnet CIDRs: session_hosts for the host pool VMs, private_endpoints for the profile share and Key Vault endpoints."
  type = object({
    session_hosts     = string
    private_endpoints = string
  })
  default = {
    session_hosts     = "10.50.0.0/22"
    private_endpoints = "10.50.4.0/27"
  }
  validation {
    condition     = can(cidrhost(var.subnets.session_hosts, 0)) && can(cidrhost(var.subnets.private_endpoints, 0))
    error_message = "Each subnet must be a CIDR block, for example 10.50.0.0/22."
  }
}

variable "dns_servers" {
  description = "Custom DNS servers (a DNS resolver or domain controllers). Empty uses Azure DNS."
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "The deployment's availability zones. Empty means the region has none (or a regional deployment): the NAT gateway IP then gets no zones."
  type        = list(string)
  default     = []
}

variable "hub_vnet_id" {
  description = "Optional hub VNet ID to peer with (firewall, DNS, on-premises). Null skips peering."
  type        = string
  default     = null
}

variable "use_remote_gateways" {
  description = "Use the hub's VPN or ExpressRoute gateway from the spoke. Only valid with hub_vnet_id."
  type        = bool
  default     = false
  validation {
    condition     = !var.use_remote_gateways || var.hub_vnet_id != null
    error_message = "use_remote_gateways needs hub_vnet_id."
  }
}

variable "create_private_dns_zones" {
  description = "Create privatelink DNS zones in this spoke. Set false when the hub owns them and pass existing_private_dns_zone_ids instead."
  type        = bool
  default     = true
}

variable "existing_private_dns_zone_ids" {
  description = "Existing privatelink zone IDs keyed by file, vault and blob. Used when create_private_dns_zones is false."
  type        = map(string)
  default     = {}
}

variable "create_nat_gateway" {
  description = "Give session hosts outbound internet through a NAT gateway. Set false when a hub firewall handles egress, and set egress_firewall_ip."
  type        = bool
  default     = true
  validation {
    condition     = var.create_nat_gateway != (var.egress_firewall_ip != null)
    error_message = "Session hosts need exactly one way out: the NAT gateway, or egress_firewall_ip with create_nat_gateway = false."
  }
}

variable "egress_firewall_ip" {
  description = "Private IP of the hub firewall that session host traffic to the internet goes through. Null keeps the NAT gateway as the way out."
  type        = string
  default     = null
  validation {
    condition     = var.egress_firewall_ip == null || can(cidrhost("${coalesce(var.egress_firewall_ip, "0.0.0.0")}/32", 0))
    error_message = "egress_firewall_ip must be an IPv4 address."
  }
}
