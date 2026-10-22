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
  value       = module.session_hosts.host_names
}

output "key_vault_name" {
  description = "Key Vault with the break-glass credential (sessionhost-localadmin-username and -password)."
  value       = module.key_vault.key_vault_name
}

output "profile_share_unc" {
  description = "FSLogix profile share."
  value       = module.fslogix.profile_share_unc
}

output "profile_storage_account_name" {
  description = "Profile storage account. Its Entra app registration needs admin consent once before Entra Kerberos works."
  value       = module.fslogix.storage_account_name
}
