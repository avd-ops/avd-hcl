output "management_group_ids" {
  description = "Map of ALZ Management Group keys to their resource IDs."
  value       = module.lab_topology.management_group_ids
}

output "subscription_ids" {
  description = "Map of active lab subscription keys to subscription UUIDs."
  value       = module.lab_topology.subscription_ids
}
