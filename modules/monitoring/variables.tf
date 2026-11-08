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

variable "subscription_id" {
  description = "Subscription resource ID (/subscriptions/<id>) for the monthly cost budget. Null skips the budget."
  type        = string
  default     = null
}

variable "alert_email_addresses" {
  description = "Email addresses for the monitoring action group and budget notifications. Empty skips the action group and budget."
  type        = list(string)
  default     = []
}

variable "monthly_budget_amount" {
  description = "Monthly cost budget in the subscription's billing currency. Null skips the budget."
  type        = number
  default     = null
  validation {
    condition     = var.monthly_budget_amount == null || var.monthly_budget_amount > 0
    error_message = "monthly_budget_amount must be greater than 0, or null."
  }
}

variable "budget_start_date" {
  description = "First of a month in RFC3339 UTC (YYYY-MM-01T00:00:00Z) for the monthly budget. Keep it fixed across applies."
  type        = string
  default     = null
  validation {
    condition     = var.budget_start_date == null || can(regex("^[0-9]{4}-[0-9]{2}-01T00:00:00Z$", var.budget_start_date))
    error_message = "budget_start_date must be the first of a month in YYYY-MM-01T00:00:00Z format, or null."
  }
}
