variable "tenant_id" {
  description = "Entra tenant ID."
  type        = string
}

variable "subscription_id" {
  description = "Subscription ID."
  type        = string
}

variable "location" {
  description = "Azure region for the host pool and session hosts."
  type        = string
}

variable "prefix" {
  description = "Pool naming prefix (e.g. avd-eng), used for host pool, app group and scaling plan."
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

variable "cloud" {
  description = "Target cloud environment profile (commercial or usgov)."
  type        = string
  default     = "commercial"
  validation {
    condition     = contains(["commercial", "usgov"], var.cloud)
    error_message = "cloud must be commercial or usgov."
  }
}

variable "tags" {
  description = "Extra tags on every resource."
  type        = map(string)
  default     = {}
}

variable "control_plane_resource_group_name" {
  description = "Existing resource group name for the host pool, app group and scaling plan."
  type        = string
}

variable "session_hosts_resource_group_name" {
  description = "Existing resource group name for session host VMs."
  type        = string
}

variable "session_hosts_resource_group_id" {
  description = "Existing resource group ID for session host VMs."
  type        = string
}

variable "existing_workspace_id" {
  description = "Existing AVD workspace ID to attach this host pool's application group to."
  type        = string
}

variable "subnet_id" {
  description = "Existing session host subnet ID."
  type        = string
}

variable "key_vault_id" {
  description = "Existing Key Vault ID for break-glass local admin secrets."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace ID for control plane diagnostic settings."
  type        = string
}

variable "data_collection_rule_id" {
  description = "Existing AVD Insights data collection rule ID."
  type        = string
}

variable "profile_share_unc" {
  description = "Existing FSLogix profile share UNC path (\\\\account.file.core.windows.net\\share)."
  type        = string
}

variable "identity_model" {
  description = "Directory join model: entra_only (default), ad_ds, or entra_ds."
  type        = string
  default     = "entra_only"
  validation {
    condition     = contains(["entra_only", "ad_ds", "entra_ds"], var.identity_model)
    error_message = "identity_model must be entra_only, ad_ds or entra_ds."
  }
}

variable "host_pool_type" {
  description = "Pooled or Personal."
  type        = string
  default     = "Pooled"
  validation {
    condition     = contains(["Pooled", "Personal"], var.host_pool_type)
    error_message = "host_pool_type must be Pooled or Personal."
  }
}

variable "personal_assignment_type" {
  description = "Automatic or Direct when host_pool_type is Personal."
  type        = string
  default     = "Automatic"
}

variable "app_group_type" {
  description = "Desktop (default) or RemoteApp."
  type        = string
  default     = "Desktop"
}

variable "remote_apps" {
  description = "Map of RemoteApp applications when app_group_type is RemoteApp."
  type = map(object({
    friendly_name                = optional(string)
    description                  = optional(string)
    path                         = string
    command_line_argument_policy = optional(string, "DoNotAllow")
    command_line_arguments       = optional(string)
    show_in_portal               = optional(bool, true)
    icon_path                    = optional(string)
    icon_index                   = optional(number, 0)
  }))
  default = {}
}

variable "max_sessions_per_host" {
  description = "Most user sessions on one host."
  type        = number
  default     = 8
}

variable "time_zone" {
  description = "Windows time zone ID for scaling plan and auto-shutdown."
  type        = string
  default     = "UTC"
}

variable "user_group_object_ids" {
  description = "Entra user group object IDs."
  type        = list(string)
}

variable "admin_group_object_ids" {
  description = "Entra admin group object IDs."
  type        = list(string)
  default     = []
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

variable "host_generation" {
  description = "Blue/green generation: empty, a, or b."
  type        = string
  default     = ""
}

variable "auto_shutdown_time" {
  description = "Daily VM auto-shutdown time in HHmm, or null."
  type        = string
  default     = null
}

variable "vm_size" {
  description = "Session host VM size."
  type        = string
  default     = "Standard_E4as_v5"
}

variable "availability_zones" {
  description = "Availability zones for session hosts."
  type        = list(string)
  default     = []
}

variable "marketplace_image" {
  description = "Marketplace image when image_id is null."
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
  description = "Compute Gallery image version ID, or null."
  type        = string
  default     = null
}

variable "encryption_at_host" {
  description = "Encrypt temp disks and caches at the host."
  type        = bool
  default     = true
}

variable "enroll_in_intune" {
  description = "Enroll Entra-joined hosts in Intune."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "AD DS or Entra DS domain FQDN when identity_model is ad_ds or entra_ds."
  type        = string
  default     = null
}

variable "domain_ou_path" {
  description = "Optional AD DS OU distinguished name."
  type        = string
  default     = null
}

variable "domain_join_username" {
  description = "Domain-join account username."
  type        = string
  default     = null
}

variable "domain_join_password_secret_url" {
  description = "Versioned Key Vault secret URI for the domain-join password."
  type        = string
  default     = null
}

variable "domain_join_key_vault_id" {
  description = "Key Vault ID holding domain_join_password_secret_url. Defaults to key_vault_id."
  type        = string
  default     = null
}

variable "local_admin_username" {
  description = "Break-glass local admin username."
  type        = string
  default     = "avdbreakglass"
}

variable "fslogix_profile_size_mib" {
  description = "Largest a profile container may grow, in MiB."
  type        = number
  default     = 30720
}

variable "enable_private_link" {
  description = "Enable AVD Private Link on this host pool."
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "Private endpoint subnet ID when enable_private_link is true."
  type        = string
  default     = null
}

variable "private_dns_zone_id" {
  description = "privatelink.wvd.microsoft.com zone ID when enable_private_link is true."
  type        = string
  default     = null
}
