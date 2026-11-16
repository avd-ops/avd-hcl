variable "tenant_id" {
  type        = string
  description = "Primary Microsoft Entra ID tenant UUID."
}

variable "subscription_id" {
  type        = string
  description = "Anchor Azure subscription UUID used by the azurerm provider during tenant-level Management Group and vending operations."
}

variable "prefix" {
  type        = string
  description = "Short lowercase prefix for Management Group IDs and vended subscription names."
  default     = "avdlz"
}

variable "root_management_group_id" {
  type        = string
  description = "Optional parent Management Group ID (defaults to Tenant Root Group when null)."
  default     = null
}

variable "vend_subscriptions" {
  type        = bool
  description = "When true, vend any primary lab subscriptions not already listed in existing_subscription_ids via MCA billing_scope_id."
  default     = false
}

variable "enable_second_workload_spoke" {
  type        = bool
  description = "When true, include a second AVD workload spoke subscription (lz-avd-workload-2) under landing-zones."
  default     = false
}

variable "billing_scope_id" {
  type        = string
  description = "MCA billing scope ID required when vend_subscriptions is true."
  default     = null
}

variable "existing_subscription_ids" {
  type        = map(string)
  description = "Map of subscription role key (platform-connectivity, platform-management, lz-avd-workload, sandbox-ci) to existing subscription UUID."
  default     = {}
}

variable "monthly_budget_amount" {
  type        = number
  description = "Monthly Azure Consumption Budget limit (USD) applied to each active primary lab subscription."
  default     = 50
}

variable "budget_start_date" {
  type        = string
  description = "RFC3339 first-of-month start date for subscription budgets (for example, 2026-11-01T00:00:00Z)."
}

variable "budget_alert_emails" {
  type        = list(string)
  description = "Email addresses notified when subscription spend crosses 50%, 80%, or 100% of monthly_budget_amount."
}

variable "ci_principal_id" {
  type        = string
  description = "Optional Entra object ID of the CI OIDC service principal granted sandbox Management Group Contributor."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to vended subscriptions."
  default = {
    project = "avd-hcl"
    purpose = "lab-topology"
  }
}
