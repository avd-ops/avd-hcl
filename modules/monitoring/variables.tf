variable "prefix" {
  description = "Short naming prefix; the AVD Insights rule is named microsoft-avdi-<prefix>."
  type        = string
}

variable "name" {
  description = "Log Analytics workspace name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for monitoring."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "retention_in_days" {
  description = "Log Analytics retention. 30 days is included in the ingestion price."
  type        = number
  default     = 30
  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}
