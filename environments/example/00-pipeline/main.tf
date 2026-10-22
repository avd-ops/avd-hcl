# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), environments/example/00-pipeline; see CREDITS.md and NOTICE.
# Changes: no repository-settings module (the github/ settings own those, one owner per setting).
#
# One-time bootstrap for the deploy pipeline: state storage, the plan and apply identities, and
# the GitHub environments that gate an apply behind a reviewer's approval. Run it from Cloud Shell
# with scripts/pipeline/bootstrap.sh; after this, plans and applies run in GitHub Actions.

module "pipeline" {
  source = "../../../modules/deploy-pipeline"

  name                = var.name
  location            = var.location
  tenant_id           = var.tenant_id
  subscription_id     = var.subscription_id
  environment         = var.environment
  github              = var.github
  storage_replication = var.storage_replication
  tags                = var.tags

  apply_roles            = var.access.apply_roles
  apply_assignable_roles = var.access.apply_assignable_roles
  apply_graph_roles      = var.access.apply_graph_roles
  plan_graph_roles       = var.access.plan_graph_roles
}
