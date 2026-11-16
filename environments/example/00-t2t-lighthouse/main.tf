# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
#
# Root for preparing the secondary Entra tenant's t2t-lab subscription and delegating it to the
# primary lab tenant via Azure Lighthouse (avd-ops ADR 0019).

module "subscription_baseline" {
  source = "../../../modules/subscription-baseline"
}

module "t2t_lighthouse" {
  source = "../../../modules/t2t-lighthouse"

  name                   = var.name
  managing_tenant_id     = var.managing_tenant_id
  target_subscription_id = var.target_subscription_id
  authorizations         = var.authorizations

  depends_on = [module.subscription_baseline]
}
