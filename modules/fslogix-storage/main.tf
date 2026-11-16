# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/fslogix-storage; see CREDITS.md and NOTICE.
# Changes: SMB channel encryption allows AES-128-GCM as well as AES-256-GCM (avd-landing-zone
# lesson 0028), shared key access is off, replication is a variable (ZRS needs a zonal region),
# shares keep deleted data for 14 days, and logs go to Log Analytics.
#
# One tenant step Terraform does not do: an admin grants consent to the storage account's
# Entra app registration once, before Entra Kerberos tickets are issued for the share.

locals {
  use_existing_storage = var.existing_storage_account_id != null
  use_existing_share   = local.use_existing_storage && var.existing_share_name != null
  effective_identity_source = var.identity_source != null ? var.identity_source : (
    var.identity_model == "ad_ds" ? "AD" : (var.identity_model == "entra_ds" ? "AADDS" : "AADKERB")
  )
  storage_account_id   = local.use_existing_storage ? var.existing_storage_account_id : azurerm_storage_account.profiles[0].id
  storage_account_name = local.use_existing_storage ? element(split("/", var.existing_storage_account_id), length(split("/", var.existing_storage_account_id)) - 1) : azurerm_storage_account.profiles[0].name
  effective_share_name = local.use_existing_share ? var.existing_share_name : azurerm_storage_share.profiles[0].name
}

resource "azurerm_storage_account" "profiles" {
  count                           = local.use_existing_storage ? 0 : 1
  name                            = var.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_kind                    = "FileStorage"
  account_tier                    = "Premium"
  account_replication_type        = var.replication_type
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false # SMB is Kerberos-only, so a key could not mount the share anyway.
  default_to_oauth_authentication = local.effective_identity_source != "AD"
  public_network_access           = "Disabled"
  allow_nested_items_to_be_public = false
  tags                            = var.tags

  azure_files_authentication {
    directory_type                 = local.effective_identity_source
    default_share_level_permission = "None"

    dynamic "active_directory" {
      for_each = local.effective_identity_source == "AD" ? [var.active_directory] : []
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
      condition     = local.effective_identity_source != "AD" || var.active_directory != null
      error_message = "active_directory must be set when the effective identity source is AD."
    }

    precondition {
      condition     = var.private_endpoint_subnet_id != null && var.private_dns_zone_id != null && var.log_analytics_workspace_id != null
      error_message = "private_endpoint_subnet_id, private_dns_zone_id and log_analytics_workspace_id are required when creating a new storage account."
    }
  }
}

resource "azurerm_storage_share" "profiles" {
  count              = local.use_existing_share ? 0 : 1
  name               = var.share_name
  storage_account_id = local.storage_account_id
  quota              = var.share_quota_gb
  enabled_protocol   = "SMB"
}

resource "azurerm_private_endpoint" "file" {
  count               = local.use_existing_storage ? 0 : 1
  name                = "pe-${var.name}-file"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "file"
    private_connection_resource_id = azurerm_storage_account.profiles[0].id
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
  scope                = local.storage_account_id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = each.value
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "admins" {
  for_each             = toset(var.admin_group_object_ids)
  scope                = local.storage_account_id
  role_definition_name = "Storage File Data SMB Share Elevated Contributor"
  principal_id         = each.value
  principal_type       = "Group"
}

resource "azurerm_monitor_diagnostic_setting" "file" {
  count                      = local.use_existing_storage ? 0 : 1
  name                       = "to-log-analytics"
  target_resource_id         = "${azurerm_storage_account.profiles[0].id}/fileServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "Transaction"
  }
}
