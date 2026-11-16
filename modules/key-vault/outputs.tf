output "key_vault_id" {
  description = "Key Vault ID."
  value       = local.key_vault_id
}

output "key_vault_name" {
  description = "Key Vault name; the break-glass secrets are sessionhost-localadmin-username and <host>-localadmin."
  value       = local.key_vault_name
}
