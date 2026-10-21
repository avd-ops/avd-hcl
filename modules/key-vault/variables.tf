variable "name" {
  description = "Key Vault name (3-24 letters, digits and single hyphens, globally unique). Purge protection keeps a deleted vault's name taken for 90 days."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Key Vault names are 3-24 letters, digits and hyphens, starting with a letter, with no two hyphens in a row."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the vault."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the vault private endpoint."
  type        = string
}

variable "private_dns_zone_id" {
  description = "privatelink.vaultcore.azure.net zone ID."
  type        = string
}

variable "local_admin_username" {
  description = "Session host local admin username, stored next to the password."
  type        = string
}

variable "admin_group_object_ids" {
  description = "Entra groups allowed to read the break-glass secrets (Key Vault Secrets User)."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for the vault's audit log."
  type        = string
}
