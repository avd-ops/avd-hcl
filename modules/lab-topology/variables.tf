variable "prefix" {
  type        = string
  description = "Short lowercase prefix for Management Group IDs (for example, avdlz)."
  default     = "avdlz"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,16}$", var.prefix))
    error_message = "prefix must be 2 to 16 lowercase alphanumeric characters or hyphens."
  }
}

variable "root_management_group_id" {
  type        = string
  description = "Optional parent Management Group ID (defaults to Tenant Root Group when null)."
  default     = null
}

variable "vend_subscriptions" {
  type        = bool
  description = "When true, vend the four primary lab subscriptions via MCA billing_scope_id; when false, associate existing_subscription_ids."
  default     = false
}

variable "billing_scope_id" {
  type        = string
  description = "MCA billing scope ID (/providers/Microsoft.Billing/billingAccounts/.../invoiceSections/...) required when vend_subscriptions is true."
  default     = null

  validation {
    condition     = !var.vend_subscriptions || (var.billing_scope_id != null && length(trimspace(var.billing_scope_id)) > 0)
    error_message = "billing_scope_id must be set when vend_subscriptions is true."
  }
}

variable "existing_subscription_ids" {
  type        = map(string)
  description = "Map of subscription role key (platform-connectivity, platform-management, lz-avd-workload, sandbox-ci) to existing subscription UUID when vend_subscriptions is false."
  default     = {}

  validation {
    condition = alltrue([
      for k in keys(var.existing_subscription_ids) :
      contains(["platform-connectivity", "platform-management", "lz-avd-workload", "sandbox-ci"], k)
    ])
    error_message = "existing_subscription_ids keys must be among platform-connectivity, platform-management, lz-avd-workload, sandbox-ci."
  }
}

variable "monthly_budget_amount" {
  type        = number
  description = "Monthly Azure Consumption Budget limit (USD) applied to each active primary lab subscription."
  default     = 50

  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "monthly_budget_amount must be greater than zero."
  }
}

variable "budget_start_date" {
  type        = string
  description = "RFC3339 first-of-month start date for subscription budgets (for example, 2026-11-01T00:00:00Z)."

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-01T00:00:00Z$", var.budget_start_date))
    error_message = "budget_start_date must be the first day of a month in YYYY-MM-01T00:00:00Z format."
  }
}

variable "budget_alert_emails" {
  type        = list(string)
  description = "Email addresses notified when subscription spend crosses 50%, 80%, or 100% of monthly_budget_amount."

  validation {
    condition     = length(var.budget_alert_emails) > 0
    error_message = "Provide at least one email address in budget_alert_emails."
  }
}

variable "ci_principal_id" {
  type        = string
  description = "Optional Entra object ID of the CI OIDC service principal granted sandbox Management Group Contributor."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to vended subscriptions."
  default     = {}
}
