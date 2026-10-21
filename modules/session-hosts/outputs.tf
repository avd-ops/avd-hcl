output "host_names" {
  description = "Session host VM names."
  value       = keys(local.hosts)
}

output "host_ids" {
  description = "Session host VM IDs keyed by name."
  value       = { for k, vm in azurerm_windows_virtual_machine.host : k => vm.id }
}
