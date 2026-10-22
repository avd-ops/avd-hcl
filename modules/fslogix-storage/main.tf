# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/fslogix-storage; see CREDITS.md and NOTICE.
# Changes: SMB channel encryption allows AES-128-GCM as well as AES-256-GCM (avd-landing-zone
# lesson 0028), shared key access is off, replication is a variable (ZRS needs a zonal region),
# shares keep deleted data for 14 days, and logs go to Log Analytics.
#
# One tenant step Terraform does not do: an admin grants consent to the storage account's
# Entra app registration once, before Entra Kerberos tickets are issued for the share.

resource "azurerm_storage_account" "profiles" {
  name                            = var.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_kind                    = "FileStorage"
  account_tier                    = "Premium"
  account_replication_type        = var.replication_type
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false # SMB is Kerberos-only, so a key could not mount the share anyway.
  default_to_oauth_authentication = true
  public_network_access           = "Disabled"
  allow_nested_items_to_be_public = false
  tags                            = var.tags

  azure_files_authentication {
    directory_type                 = var.identity_source
    default_share_level_permission = "None"

    dynamic "active_directory" {
      for_each = var.identity_source == "AD" ? [var.active_directory] : []
      content {
        domain_name         = active_directory.value.domain_name
        domain_guid         = active_directory.value.domain_guid
        domain_sid          = active_directory.value.domain_sid
        forest_name         = active_directory.value.forest_name
        netbios_domain_name = active_directory.value.netbios_domain_name
        storage_sid         = active_directory.value.storage_sid
      }
    }
  }

  share_properties {
    retention_policy {
      days = 14
    }

    smb {
      versions                        = ["SMB3.1.1"]
      authentication_types            = ["Kerberos"]
      kerberos_ticket_encryption_type = ["AES-256"]
      # AES-128-GCM must stay allowed: with AES-256-GCM alone, Azure Files rejects an Entra
      # Kerberos session setup from a cloud-only user and FSLogix fails with "Access is denied"
      # (avd-landing-zone lesson 0028).
      channel_encryption_type = ["AES-128-GCM", "AES-256-GCM"]
      multichannel_enabled    = true
    }
  }

  lifecycle {
    precondition {
      condition     = var.identity_source != "AD" || var.active_directory != null
      error_message = "active_directory must be set when identity_source is AD."
    }
  }
}

resource "azurerm_storage_share" "profiles" {
  name               = var.share_name
  storage_account_id = azurerm_storage_account.profiles.id
  quota              = var.share_quota_gb
  enabled_protocol   = "SMB"
}

resource "azurerm_private_endpoint" "file" {
  name                = "pe-${var.name}-file"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "file"
    private_connection_resource_id = azurerm_storage_account.profiles.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "users" {
  for_each             = toset(var.user_group_object_ids)
  scope                = azurerm_storage_account.profiles.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = each.value
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "admins" {
  for_each             = toset(var.admin_group_object_ids)
  scope                = azurerm_storage_account.profiles.id
  role_definition_name = "Storage File Data SMB Share Elevated Contributor"
  principal_id         = each.value
  principal_type       = "Group"
}

resource "azurerm_monitor_diagnostic_setting" "file" {
  name                       = "to-log-analytics"
  target_resource_id         = "${azurerm_storage_account.profiles.id}/fileServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "Transaction"
  }
}
