output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID, for diagnostic settings."
  value       = azurerm_log_analytics_workspace.avd.id
}

output "data_collection_rule_id" {
  description = "AVD Insights data collection rule ID, associated with every session host."
  value       = azurerm_monitor_data_collection_rule.avd_insights.id
}

output "action_group_id" {
  description = "Action group ID when alert_email_addresses is set, else null."
  value       = try(azurerm_monitor_action_group.avd[0].id, null)
}
