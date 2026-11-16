mock_provider "azurerm" {
  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttestprofiles"
    }
  }
}

variables {
  name                       = "sttestprofiles"
  location                   = "eastus2"
  resource_group_name        = "rg-test"
  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-private-endpoints"
  private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
  user_group_object_ids      = ["00000000-0000-0000-0000-000000000001"]
  admin_group_object_ids     = ["00000000-0000-0000-0000-000000000002"]
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
}

# avd-landing-zone lesson 0028: AES-256-GCM alone denies Entra Kerberos sign-ins from cloud-only users.
run "channel_encryption_allows_aes_128_gcm" {
  command = plan

  assert {
    condition     = toset(one(one(azurerm_storage_account.profiles[0].share_properties).smb).channel_encryption_type) == toset(["AES-128-GCM", "AES-256-GCM"])
    error_message = "SMB channel encryption must allow AES-128-GCM and AES-256-GCM."
  }

  assert {
    condition     = one(azurerm_storage_account.profiles[0].azure_files_authentication).directory_type == "AADKERB"
    error_message = "Entra Kerberos is the default identity source."
  }

  assert {
    condition     = !azurerm_storage_account.profiles[0].shared_access_key_enabled
    error_message = "Shared key access stays off."
  }

  assert {
    condition     = output.profile_share_unc == "\\\\sttestprofiles.file.core.windows.net\\profiles"
    error_message = "Unexpected profile share UNC path."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.file[0].log_analytics_workspace_id == var.log_analytics_workspace_id
    error_message = "File service logs go to Log Analytics."
  }
}

run "ad_needs_domain_details" {
  command = plan

  variables {
    identity_source = "AD"
  }

  expect_failures = [azurerm_storage_account.profiles]
}

run "bad_name_is_rejected" {
  command = plan

  variables {
    name = "Not-Valid"
  }

  expect_failures = [var.name]
}

run "ad_ds_identity_model_uses_ad_smb" {
  command = plan

  variables {
    identity_model = "ad_ds"
    active_directory = {
      domain_name         = "corp.contoso.com"
      domain_guid         = "00000000-0000-0000-0000-000000000010"
      netbios_domain_name = "CONTOSO"
    }
  }

  assert {
    condition     = one(azurerm_storage_account.profiles[0].azure_files_authentication).directory_type == "AD"
    error_message = "ad_ds identity_model configures Azure Files for AD DS SMB."
  }

  assert {
    condition     = one(one(azurerm_storage_account.profiles[0].azure_files_authentication).active_directory).domain_name == "corp.contoso.com"
    error_message = "Active Directory domain details are wired to azure_files_authentication."
  }
}

run "existing_storage_account_and_share_are_reused" {
  command = plan

  variables {
    existing_storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-storage/providers/Microsoft.Storage/storageAccounts/stexistingavd"
    existing_share_name         = "avdprofiles"
    private_endpoint_subnet_id  = null
    private_dns_zone_id         = null
    log_analytics_workspace_id  = null
  }

  assert {
    condition     = length(azurerm_storage_account.profiles) == 0 && length(azurerm_storage_share.profiles) == 0 && length(azurerm_private_endpoint.file) == 0 && length(azurerm_monitor_diagnostic_setting.file) == 0
    error_message = "Reusing an existing storage account and share skips creating them."
  }

  assert {
    condition     = output.storage_account_id == var.existing_storage_account_id && output.storage_account_name == "stexistingavd" && output.profile_share_unc == "\\\\stexistingavd.file.core.windows.net\\avdprofiles"
    error_message = "Existing storage account and share flow through outputs."
  }
}

run "entra_ds_identity_model_uses_aadds" {
  command = plan

  variables {
    identity_model = "entra_ds"
  }

  assert {
    condition     = one(azurerm_storage_account.profiles[0].azure_files_authentication).directory_type == "AADDS"
    error_message = "entra_ds identity_model configures Azure Files for AADDS."
  }
}

run "usgov_uses_gov_file_endpoint_in_unc" {
  command = plan

  variables {
    cloud    = "usgov"
    location = "usgovvirginia"
  }

  assert {
    condition     = output.profile_share_unc == "\\\\sttestprofiles.file.core.usgovcloudapi.net\\profiles"
    error_message = "usgov cloud must use file.core.usgovcloudapi.net in profile_share_unc."
  }
}
