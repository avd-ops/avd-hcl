output "host_names" {
  description = "Session host VM names."
  value       = keys(local.hosts)
}

output "host_ids" {
  description = "Session host VM IDs keyed by name."
  value       = { for k, vm in azapi_resource.host : k => vm.id }
}
