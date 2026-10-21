output "key_vault_id" {
  description = "Key Vault ID."
  value       = azurerm_key_vault.this.id
}

output "key_vault_name" {
  description = "Key Vault name; the break-glass secrets are sessionhost-localadmin-username and -password."
  value       = azurerm_key_vault.this.name
}
