# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/fslogix-storage; see CREDITS.md and NOTICE.

variable "name" {
  description = "Storage account name (3-24 lowercase letters and digits, globally unique)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Storage account names must be 3-24 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for profile storage."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "share_name" {
  description = "Azure Files share for FSLogix profile containers."
  type        = string
  default     = "profiles"
}

variable "share_quota_gb" {
  description = "Provisioned share size in GiB. Premium shares bill on provisioned size and scale IOPS with it."
  type        = number
  default     = 1024
  validation {
    condition     = var.share_quota_gb >= 100
    error_message = "Premium file shares start at 100 GiB."
  }
}

variable "identity_model" {
  description = "Directory join model: entra_only (Entra Kerberos, default), ad_ds (AD DS SMB), or entra_ds (Entra Domain Services). Overridden when identity_source is set explicitly."
  type        = string
  default     = "entra_only"
  validation {
    condition     = contains(["entra_only", "ad_ds", "entra_ds"], var.identity_model)
    error_message = "identity_model must be entra_only, ad_ds or entra_ds."
  }
}

variable "identity_source" {
  description = "Optional explicit Azure Files authentication directory_type: AADKERB, AADDS, or AD. Null derives it from identity_model."
  type        = string
  default     = null
  validation {
    condition     = var.identity_source == null || contains(["AADKERB", "AADDS", "AD"], var.identity_source)
    error_message = "identity_source must be AADKERB, AADDS, AD, or null."
  }
}

variable "active_directory" {
  description = "AD DS domain details. Required when effective identity source is AD; the computer account must be created with AzFilesHybrid separately."
  type = object({
    domain_name         = string
    domain_guid         = string
    domain_sid          = optional(string)
    forest_name         = optional(string)
    netbios_domain_name = optional(string)
    storage_sid         = optional(string)
  })
  default = null
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the file private endpoint. Required when creating a new storage account."
  type        = string
  default     = null
}

variable "private_dns_zone_id" {
  description = "privatelink.file.core.windows.net zone ID. Required when creating a new storage account."
  type        = string
  default     = null
}

variable "user_group_object_ids" {
  description = "Entra groups of AVD users, granted Storage File Data SMB Share Contributor."
  type        = list(string)
  default     = []
}

variable "admin_group_object_ids" {
  description = "Entra groups of profile admins, granted Storage File Data SMB Share Elevated Contributor."
  type        = list(string)
  default     = []
}

variable "replication_type" {
  description = "LRS, or ZRS in a region with availability zones (Premium ZRS fails where there are none)."
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "ZRS"], var.replication_type)
    error_message = "replication_type must be LRS or ZRS."
  }
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for the file service's logs and transaction metrics. Required when creating a new storage account."
  type        = string
  default     = null
}

variable "existing_storage_account_id" {
  description = "Existing storage account ID for FSLogix profiles. When set, no new storage account, private endpoint or diagnostic setting is created."
  type        = string
  default     = null
}

variable "existing_share_name" {
  description = "Existing file share name on existing_storage_account_id. When set with existing_storage_account_id, skips creating the file share."
  type        = string
  default     = null
}
