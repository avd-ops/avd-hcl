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
    condition     = toset(one(one(azurerm_storage_account.profiles.share_properties).smb).channel_encryption_type) == toset(["AES-128-GCM", "AES-256-GCM"])
    error_message = "SMB channel encryption must allow AES-128-GCM and AES-256-GCM."
  }

  assert {
    condition     = one(azurerm_storage_account.profiles.azure_files_authentication).directory_type == "AADKERB"
    error_message = "Entra Kerberos is the default identity source."
  }

  assert {
    condition     = !azurerm_storage_account.profiles.shared_access_key_enabled
    error_message = "Shared key access stays off."
  }

  assert {
    condition     = output.profile_share_unc == "\\\\sttestprofiles.file.core.windows.net\\profiles"
    error_message = "Unexpected profile share UNC path."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.file.log_analytics_workspace_id == var.log_analytics_workspace_id
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
