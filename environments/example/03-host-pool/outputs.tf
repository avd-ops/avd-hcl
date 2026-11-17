output "host_pool_id" {
  description = "Host pool ID."
  value       = module.control_plane.host_pool_id
}

output "host_pool_name" {
  description = "Host pool name."
  value       = module.control_plane.host_pool_name
}

output "app_group_id" {
  description = "Application group ID."
  value       = module.control_plane.app_group_id
}

output "session_host_names" {
  description = "Session host VM names."
  value       = var.host_placement == "azure" ? module.session_hosts[0].host_names : module.azure_local_session_hosts[0].host_names
}

output "azure_local" {
  description = "Azure Local placement metadata when host_placement is azure-local; null otherwise."
  value = var.host_placement == "azure-local" ? {
    host_placement             = var.host_placement
    custom_location_id         = var.custom_location_id
    logical_network_id         = var.azure_local_logical_network_id
    vm_instance_ids            = module.azure_local_session_hosts[0].vm_instance_ids
    hybrid_compute_machine_ids = module.azure_local_session_hosts[0].hybrid_compute_machine_ids
  } : null
}
