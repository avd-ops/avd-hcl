output "resource_group_name" {
  description = "Resource group with the state storage and deploy identities."
  value       = module.pipeline.resource_group_name
}

output "storage_account_name" {
  description = "Storage account for Terraform state, saved plans and answers."
  value       = module.pipeline.storage_account_name
}

output "github_environments" {
  description = "GitHub environments the deploy workflow uses."
  value       = module.pipeline.github_environments
}

output "environment" {
  description = "Kit environment this pipeline deploys."
  value       = var.environment
}
