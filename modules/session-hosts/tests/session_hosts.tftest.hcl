mock_provider "azurerm" {
  mock_resource "azurerm_network_interface" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkInterfaces/nic-test"
    }
  }
}

mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Compute/virtualMachines/vm-test"
    }
  }
}

variables {
  location                = "eastus2"
  resource_group_name     = "rg-test"
  resource_group_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
  name_prefix             = "avdtest"
  host_count              = 3
  availability_zones      = ["1", "2"]
  subnet_id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-session-hosts"
  local_admin_password    = "Placeholder-only-for-tests-1!"
  key_vault_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
  registration_token      = "placeholder-only-for-tests"
  data_collection_rule_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/dataCollectionRules/microsoft-avdi-test"
  profile_share_unc       = "\\\\sttestprofiles.file.core.windows.net\\profiles"
  user_group_object_ids   = ["00000000-0000-0000-0000-000000000001"]
  admin_group_object_ids  = ["00000000-0000-0000-0000-000000000002"]
}

run "hosts_spread_over_zones" {
  command = plan

  assert {
    condition     = output.host_names == ["avdtest-001", "avdtest-002", "avdtest-003"]
    error_message = "Hosts are named <prefix>-NNN."
  }

  assert {
    condition     = azapi_resource.host["avdtest-001"].body.zones == ["1"] && azapi_resource.host["avdtest-002"].body.zones == ["2"] && azapi_resource.host["avdtest-003"].body.zones == ["1"]
    error_message = "Hosts go round robin over the zones."
  }

  assert {
    condition     = azapi_resource.host["avdtest-001"].body.properties.securityProfile.securityType == "TrustedLaunch"
    error_message = "Hosts are Trusted Launch."
  }

  assert {
    condition     = azapi_resource.host["avdtest-001"].body.properties.licenseType == "Windows_Client"
    error_message = "Multi-session hosts use Windows client licensing."
  }

  assert {
    condition     = !can(azapi_resource.host["avdtest-001"].body.properties.osProfile.adminPassword)
    error_message = "The admin password must only travel in the write-only sensitive_body."
  }

  assert {
    condition     = azapi_resource_action.local_admin_password["avdtest-002"].resource_id == "${var.key_vault_id}/secrets/avdtest-002-localadmin" && azapi_resource_action.local_admin_password["avdtest-002"].method == "PUT"
    error_message = "Each host gets its own break-glass secret."
  }

  assert {
    condition     = azurerm_virtual_machine_extension.entra_join["avdtest-001"].settings == null
    error_message = "No Intune enrollment unless asked."
  }

  assert {
    condition     = azapi_resource.register_agent["avdtest-001"].body.properties.treatFailureAsDeploymentFailure && !azapi_resource.register_agent["avdtest-001"].body.properties.asyncExecution
    error_message = "A failing registration script must fail the apply."
  }

  assert {
    condition     = !can(azapi_resource.register_agent["avdtest-001"].body.properties.protectedParameters)
    error_message = "The registration token must only travel in the write-only sensitive_body."
  }
}

run "regional_hosts_and_intune" {
  command = plan

  variables {
    availability_zones = []
    enroll_in_intune   = true
    host_count         = 1
  }

  assert {
    condition     = !can(azapi_resource.host["avdtest-001"].body.zones)
    error_message = "No zones in a region without them."
  }

  assert {
    condition     = jsondecode(azurerm_virtual_machine_extension.entra_join["avdtest-001"].settings).mdmId == "0000000a-0000-0000-c000-000000000000"
    error_message = "Intune enrollment passes Intune's MDM ID to the join extension."
  }
}

run "gallery_image" {
  command = plan

  variables {
    image_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Compute/galleries/gal_test/images/avd/versions/1.0.0"
    marketplace_image = null
  }

  assert {
    condition     = azapi_resource.host["avdtest-001"].body.properties.storageProfile.imageReference.id == var.image_id
    error_message = "A gallery image replaces the marketplace reference."
  }
}

run "one_image_source_only" {
  command = plan

  variables {
    image_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Compute/galleries/gal_test/images/avd/versions/1.0.0"
  }

  expect_failures = [azapi_resource.host]
}

run "long_prefix_is_rejected" {
  command = plan

  variables {
    name_prefix = "much-too-long-prefix"
  }

  expect_failures = [var.name_prefix]
}

run "blue_green_generation_and_auto_shutdown" {
  command = plan

  variables {
    name_prefix        = "elevenchars"
    host_generation    = "a"
    host_count         = 2
    auto_shutdown_time = "2000"
    time_zone          = "Eastern Standard Time"
  }

  assert {
    condition     = output.host_names == ["elevenchara-001", "elevenchara-002"] && length(output.host_names[0]) <= 15
    error_message = "Generation trims a 11-character prefix to 10 plus the generation so names stay within 15 characters."
  }

  assert {
    condition     = azurerm_dev_test_global_vm_shutdown_schedule.host["elevenchara-001"].daily_recurrence_time == "2000" && azurerm_dev_test_global_vm_shutdown_schedule.host["elevenchara-001"].timezone == "Eastern Standard Time"
    error_message = "Daily auto-shutdown schedule is created per host when auto_shutdown_time is set."
  }
}

run "bad_generation_is_rejected" {
  command = plan

  variables {
    host_generation = "c"
  }

  expect_failures = [var.host_generation]
}

run "bad_auto_shutdown_time_is_rejected" {
  command = plan

  variables {
    auto_shutdown_time = "2500"
  }

  expect_failures = [var.auto_shutdown_time]
}

run "ad_ds_domain_join_uses_key_vault_extension" {
  command = plan

  variables {
    host_count                      = 1
    identity_model                  = "ad_ds"
    domain_name                     = "corp.contoso.com"
    domain_ou_path                  = "OU=AVD,DC=corp,DC=contoso,DC=com"
    domain_join_username            = "avdjoin@contoso.com"
    domain_join_password_secret_url = "https://kv-test.vault.azure.net/secrets/domain-join-password/00000000000000000000000000000001"
  }

  assert {
    condition     = length(azurerm_virtual_machine_extension.entra_join) == 0 && length(azurerm_virtual_machine_extension.ad_join) == 1
    error_message = "ad_ds uses JsonADDomainExtension instead of AADLoginForWindows."
  }

  assert {
    condition     = jsondecode(azurerm_virtual_machine_extension.ad_join["avdtest-001"].settings).Name == "corp.contoso.com" && jsondecode(azurerm_virtual_machine_extension.ad_join["avdtest-001"].settings).OUPath == "OU=AVD,DC=corp,DC=contoso,DC=com" && jsondecode(azurerm_virtual_machine_extension.ad_join["avdtest-001"].settings).User == "avdjoin@contoso.com"
    error_message = "Domain name, OU path and username are passed to JsonADDomainExtension."
  }

  assert {
    condition     = one(azurerm_virtual_machine_extension.ad_join["avdtest-001"].protected_settings_from_key_vault).secret_url == var.domain_join_password_secret_url && one(azurerm_virtual_machine_extension.ad_join["avdtest-001"].protected_settings_from_key_vault).source_vault_id == var.key_vault_id
    error_message = "Domain-join password is read from Key Vault without entering state."
  }
}

run "ad_ds_requires_domain_join_inputs" {
  command = plan

  variables {
    host_count     = 1
    identity_model = "ad_ds"
  }

  expect_failures = [azurerm_virtual_machine_extension.ad_join]
}
