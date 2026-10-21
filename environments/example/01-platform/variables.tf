# Every variable here is answered through schema/parameters.json (the chat, the CLI and the
# Actions form all read it). Change a default there and here together.

variable "tenant_id" {
  description = "Entra tenant ID. Read from the signed-in account, never asked or saved."
  type        = string
}

variable "subscription_id" {
  description = "Subscription to deploy into. Read from the signed-in account, never asked or saved."
  type        = string
}

variable "environment" {
  description = "sandbox, dev or prod. Sets the environment tag."
  type        = string
  default     = "sandbox"
  validation {
    condition     = contains(["sandbox", "dev", "prod"], var.environment)
    error_message = "environment must be sandbox, dev or prod."
  }
}

variable "location" {
  description = "Azure region for everything."
  type        = string
}

variable "prefix" {
  description = "Naming prefix: 2-13 lowercase letters, digits or hyphens, for example avd-dev."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.prefix)) && length(var.prefix) >= 2 && length(var.prefix) <= 13
    error_message = "prefix must be 2-13 lowercase letters, digits or single hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "tags" {
  description = "Extra tags on every resource."
  type        = map(string)
  default     = {}
}

variable "availability_zones" {
  description = "Zones to spread hosts over. Empty for a region without zones (then the NAT IP is regional and the profile share LRS)."
  type        = list(string)
  default     = []
}

variable "address_space" {
  description = "Address space for the AVD spoke VNet."
  type        = list(string)
  default     = ["10.50.0.0/20"]
}

variable "subnets" {
  description = "Subnet CIDRs inside address_space."
  type = object({
    session_hosts     = string
    private_endpoints = string
  })
  default = {
    session_hosts     = "10.50.0.0/22"
    private_endpoints = "10.50.4.0/27"
  }
}

variable "dns_servers" {
  description = "Custom DNS servers. Empty uses Azure DNS."
  type        = list(string)
  default     = []
}

variable "hub_vnet_id" {
  description = "Hub VNet to peer with. Null for a standalone spoke."
  type        = string
  default     = null
}

variable "create_nat_gateway" {
  description = "Outbound internet through a NAT gateway. Turn off when a hub firewall handles egress."
  type        = bool
  default     = true
}

variable "egress_firewall_ip" {
  description = "Hub firewall IP that session host internet traffic routes to, with create_nat_gateway = false."
  type        = string
  default     = null
}

variable "grant_avd_power_role" {
  description = "Grant the AVD service principal Power On Off Contributor on the subscription. Only one environment (or the landing zone) per subscription should; set false in the others."
  type        = bool
  default     = true
}

variable "user_group_object_ids" {
  description = "Entra groups of AVD users (object IDs)."
  type        = list(string)
  validation {
    condition     = length(var.user_group_object_ids) > 0
    error_message = "At least one user group is needed, or nobody can sign in."
  }
}

variable "admin_group_object_ids" {
  description = "Entra groups of AVD admins (object IDs): host admin sign-in, profile admin and break-glass secret access."
  type        = list(string)
  default     = []
}

variable "avd_service_principal_object_id" {
  description = "Object ID of the Azure Virtual Desktop service principal. Null looks it up, which needs directory read access."
  type        = string
  default     = null
}

variable "host_pool_friendly_name" {
  description = "Host pool display name."
  type        = string
  default     = null
}

variable "workspace_friendly_name" {
  description = "Workspace name users see in the Windows App feed."
  type        = string
  default     = "Virtual Desktop"
}

variable "max_sessions_per_host" {
  description = "Most user sessions on one host."
  type        = number
  default     = 8
}

variable "time_zone" {
  description = "Windows time zone ID for the scaling plan, for example \"Eastern Standard Time\"."
  type        = string
  default     = "UTC"
}

variable "host_count" {
  description = "Number of session hosts."
  type        = number
  default     = 1
}

variable "vm_prefix" {
  description = "Session host name prefix, up to 11 characters."
  type        = string
  default     = "avdsh"
}

variable "vm_size" {
  description = "Session host VM size."
  type        = string
  default     = "Standard_E4as_v5"
}

variable "marketplace_image" {
  description = "Marketplace image, used when image_id is null."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "office-365"
    sku       = "win11-24h2-avd-m365"
    version   = "latest"
  }
}

variable "image_id" {
  description = "Azure Compute Gallery image version ID from the image pipeline. Null uses marketplace_image."
  type        = string
  default     = null
}

variable "encryption_at_host" {
  description = "Encryption at host for the session hosts. Needs the EncryptionAtHost feature on the subscription."
  type        = bool
  default     = true
}

variable "enroll_in_intune" {
  description = "Enroll the hosts in Intune when they join Entra ID."
  type        = bool
  default     = false
}

variable "local_admin_username" {
  description = "Break-glass local admin username. The password is generated and kept in Key Vault."
  type        = string
  default     = "avdbreakglass"
}

variable "fslogix_share_quota_gb" {
  description = "Provisioned profile share size in GiB (Premium bills on size)."
  type        = number
  default     = 100
}

variable "fslogix_profile_size_mib" {
  description = "Largest a profile container may grow, in MiB."
  type        = number
  default     = 30720
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}
