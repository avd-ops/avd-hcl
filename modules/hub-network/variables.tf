# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

variable "prefix" {
  description = "Naming prefix for hub resources."
  type        = string
  default     = "avd-hub"
}

variable "cloud" {
  description = "Target cloud environment profile (commercial or usgov)."
  type        = string
  default     = "commercial"

  validation {
    condition     = contains(["commercial", "usgov"], var.cloud)
    error_message = "cloud must be commercial or usgov."
  }
}

variable "environment" {
  description = "Deployment environment (dev, test, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test, or prod."
  }
}

variable "profile" {
  description = "Cost/feature profile (lab or enterprise)."
  type        = string
  default     = "lab"

  validation {
    condition     = contains(["lab", "enterprise"], var.profile)
    error_message = "profile must be lab or enterprise."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name for the Connectivity hub."
  type        = string
}

variable "hub_address_prefix" {
  description = "CIDR block for the hub VNet."
  type        = string
  default     = "10.0.0.0/16"
}

variable "gateway_subnet_prefix" {
  description = "GatewaySubnet CIDR."
  type        = string
  default     = "10.0.0.0/26"
}

variable "firewall_subnet_prefix" {
  description = "AzureFirewallSubnet CIDR."
  type        = string
  default     = "10.0.1.0/26"
}

variable "firewall_management_subnet_prefix" {
  description = "AzureFirewallManagementSubnet CIDR (used when firewall_sku_tier is Basic)."
  type        = string
  default     = "10.0.2.0/26"
}

variable "bastion_subnet_prefix" {
  description = "AzureBastionSubnet CIDR."
  type        = string
  default     = "10.0.3.0/26"
}

variable "dns_inbound_subnet_prefix" {
  description = "DNS Private Resolver inbound subnet CIDR."
  type        = string
  default     = "10.0.4.0/28"
}

variable "dns_outbound_subnet_prefix" {
  description = "DNS Private Resolver outbound subnet CIDR."
  type        = string
  default     = "10.0.4.16/28"
}

variable "spoke_address_spaces" {
  description = "Spoke CIDR blocks permitted through the hub firewall."
  type        = list(string)
  default     = ["10.100.0.0/16"]
}

variable "availability_zones" {
  description = "Availability zones for public IPs and firewall; empty for regional."
  type        = list(string)
  default     = []
}

variable "deploy_firewall" {
  description = "Deploy Azure Firewall and Firewall Policy."
  type        = bool
  default     = true
}

variable "firewall_sku_tier" {
  description = "Azure Firewall SKU tier (Basic, Standard, Premium). Null defaults from profile."
  type        = string
  default     = null
}

variable "firewall_public_ip_count" {
  description = "Number of data public IPs for SNAT scaling (Basic always uses 1). Null defaults from profile."
  type        = number
  default     = null
}

variable "enable_shortpath_public" {
  description = "Allow UDP 3478 (STUN/TURN) for RDP Shortpath on public networks."
  type        = bool
  default     = true
}

variable "deploy_private_dns_zones" {
  description = "Deploy central Private DNS zones (file, keyVault, avd, avdGlobal)."
  type        = bool
  default     = true
}

variable "deploy_private_resolver" {
  description = "Deploy Azure DNS Private Resolver. Null defaults from profile (true for enterprise)."
  type        = bool
  default     = null
}

variable "deploy_bastion" {
  description = "Deploy shared Azure Bastion. Null defaults from profile (true for enterprise)."
  type        = bool
  default     = null
}

variable "deploy_gateway" {
  description = "Deploy VPN or ExpressRoute Virtual Network Gateway (off by default)."
  type        = bool
  default     = false
}

variable "gateway_type" {
  description = "Gateway type (Vpn or ExpressRoute)."
  type        = string
  default     = "Vpn"
}

variable "gateway_sku" {
  description = "Virtual Network Gateway SKU."
  type        = string
  default     = "VpnGw2AZ"
}

variable "tags" {
  description = "Tags applied to all hub resources."
  type        = map(string)
  default     = {}
}
