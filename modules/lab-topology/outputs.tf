output "management_group_ids" {
  description = "Map of ALZ Management Group keys to their resource IDs."
  value       = local.management_groups
}

output "subscription_ids" {
  description = "Map of active lab subscription keys to subscription UUIDs."
  value       = local.active_subscription_ids
}
