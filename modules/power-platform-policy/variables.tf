# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

variable "cloud" {
  description = "Target cloud environment profile (commercial or usgov)."
  type        = string
  default     = "commercial"

  validation {
    condition     = contains(["commercial", "usgov"], var.cloud)
    error_message = "cloud must be commercial or usgov."
  }
}

variable "enterprise_policy_name" {
  description = "Name of the Power Platform VNet enterprise policy."
  type        = string
  default     = "ep-avd-powerplatform"
}

variable "location" {
  description = "Azure region for the enterprise policy."
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the resource group that hosts the enterprise policy."
  type        = string
}

variable "delegated_subnet_id" {
  description = "Resource ID of the delegated subnet for Power Platform VNet injection."
  type        = string
}

variable "tags" {
  description = "Tags applied to the enterprise policy."
  type        = map(string)
  default     = {}
}
