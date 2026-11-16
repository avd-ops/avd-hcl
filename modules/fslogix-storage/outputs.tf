# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/fslogix-storage; see CREDITS.md and NOTICE.

output "storage_account_id" {
  description = "Profile storage account ID."
  value       = local.storage_account_id
}

output "storage_account_name" {
  description = "Profile storage account name."
  value       = local.storage_account_name
}

output "profile_share_unc" {
  description = "UNC path for the FSLogix VHDLocations setting."
  value       = "\\\\${local.storage_account_name}.file.core.windows.net\\${local.effective_share_name}"
}
