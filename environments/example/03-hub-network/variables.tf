# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

variable "subscription_id" {
  description = "Connectivity subscription ID."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant ID."
  type        = string
}

variable "prefix" {
  description = "Naming prefix for hub resources."
  type        = string
  default     = "avd-hub"
}

variable "cloud" {
  description = "Target cloud environment profile (commercial or usgov)."
  type        = string
  default     = "commercial"
}

variable "environment" {
  description = "Deployment environment (dev, test, prod)."
  type        = string
  default     = "dev"
}

variable "profile" {
  description = "Cost/feature profile (lab or enterprise)."
  type        = string
  default     = "lab"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus2"
}

variable "tags" {
  description = "Tags applied to all hub resources."
  type        = map(string)
  default = {
    workload  = "avd-connectivity"
    managedBy = "avd-hcl"
  }
}
