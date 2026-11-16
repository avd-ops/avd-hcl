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
  value       = module.session_hosts.host_names
}
