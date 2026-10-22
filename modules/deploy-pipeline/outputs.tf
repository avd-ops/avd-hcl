# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/deploy-pipeline/outputs.tf; see CREDITS.md and NOTICE.

output "resource_group_name" {
  description = "Resource group holding the state storage and the deploy identities."
  value       = azurerm_resource_group.this.name
}

output "storage_account_name" {
  description = "Storage account for Terraform state (tfstate), saved plans (plans) and answers (answers)."
  value       = azurerm_storage_account.state.name
}

output "storage_account_id" {
  description = "Resource ID of the state storage account."
  value       = azurerm_storage_account.state.id
}

output "github_environments" {
  description = "The GitHub environments the deploy workflow uses."
  value       = local.environments
}

output "plan_principal_id" {
  description = "Object ID of the plan identity. Not a secret."
  value       = local.identities.plan.principal_id
}

output "apply_principal_id" {
  description = "Object ID of the apply identity. Not a secret."
  value       = local.identities.apply.principal_id
}
