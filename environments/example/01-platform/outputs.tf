output "resource_group_names" {
  description = "Resource groups keyed by role."
  value       = module.foundation.resource_group_names
}

output "host_pool_name" {
  description = "Host pool name."
  value       = module.control_plane.host_pool_name
}

output "session_host_names" {
  description = "Session host VM names."
  value       = var.host_placement == "azure" ? module.session_hosts[0].host_names : module.azure_local_session_hosts[0].host_names
}

output "key_vault_name" {
  description = "Key Vault with the break-glass credential (sessionhost-localadmin-username and -password)."
  value       = module.key_vault.key_vault_name
}

output "profile_share_unc" {
  description = "FSLogix profile share."
  value       = var.host_placement == "azure" ? module.fslogix[0].profile_share_unc : var.local_smb_profile_path
}

output "profile_storage_account_name" {
  description = "Profile storage account. Its Entra app registration needs admin consent once before Entra Kerberos works."
  value       = var.host_placement == "azure" ? module.fslogix[0].storage_account_name : ""
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
