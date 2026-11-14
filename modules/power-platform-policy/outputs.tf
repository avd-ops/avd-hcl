# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

output "cloud" {
  description = "Target cloud environment profile."
  value       = var.cloud
}

output "enterprise_policy_status" {
  description = "Deployment status of the Power Platform VNet enterprise policy."
  value       = local.vnet_injection_supported ? "deployed" : "skipped: unsupported-in-usgov"
}

output "enterprise_policy_id" {
  description = "Resource ID of the Power Platform enterprise policy, or empty string when skipped."
  value       = local.vnet_injection_supported ? azapi_resource.vnet_policy[0].id : ""
}
