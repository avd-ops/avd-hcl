# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/fslogix-storage; see CREDITS.md and NOTICE.

output "storage_account_id" {
  description = "Profile storage account ID."
  value       = azurerm_storage_account.profiles.id
}

output "storage_account_name" {
  description = "Profile storage account name."
  value       = azurerm_storage_account.profiles.name
}

output "profile_share_unc" {
  description = "UNC path for the FSLogix VHDLocations setting."
  value       = "\\\\${azurerm_storage_account.profiles.name}.file.core.windows.net\\${azurerm_storage_share.profiles.name}"
}
