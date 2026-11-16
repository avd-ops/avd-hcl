output "registered_providers" {
  description = "Map of registered Resource Provider namespaces on the secondary lab subscription."
  value       = module.subscription_baseline.registered_providers
}

output "lighthouse_definition_id" {
  description = "Resource ID of the Azure Lighthouse registration definition."
  value       = module.t2t_lighthouse.lighthouse_definition_id
}

output "lighthouse_assignment_id" {
  description = "Resource ID of the Azure Lighthouse registration assignment."
  value       = module.t2t_lighthouse.lighthouse_assignment_id
}
