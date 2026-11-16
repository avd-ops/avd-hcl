# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
#
# Root for bootstrapping the 4-subscription ALZ primary tenant topology (avd-ops ADR 0019):
#   platform/connectivity -> platform-connectivity
#   platform/management   -> platform-management
#   landing-zones         -> lz-avd-workload
#   sandbox               -> sandbox-ci
#   decommissioned        -> (empty holding group)

module "lab_topology" {
  source = "../../../modules/lab-topology"

  prefix                       = var.prefix
  root_management_group_id     = var.root_management_group_id
  vend_subscriptions           = var.vend_subscriptions
  enable_second_workload_spoke = var.enable_second_workload_spoke
  billing_scope_id             = var.billing_scope_id
  existing_subscription_ids    = var.existing_subscription_ids
  monthly_budget_amount        = var.monthly_budget_amount
  budget_start_date            = var.budget_start_date
  budget_alert_emails          = var.budget_alert_emails
  ci_principal_id              = var.ci_principal_id
  tags                         = var.tags
}
