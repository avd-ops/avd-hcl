mock_provider "azurerm" {
  mock_resource "azurerm_network_interface" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkInterfaces/nic-test"
    }
  }
  mock_resource "azurerm_windows_virtual_machine" {
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
    condition     = azurerm_windows_virtual_machine.host["avdtest-001"].zone == "1" && azurerm_windows_virtual_machine.host["avdtest-002"].zone == "2" && azurerm_windows_virtual_machine.host["avdtest-003"].zone == "1"
    error_message = "Hosts go round robin over the zones."
  }

  assert {
    condition     = azurerm_windows_virtual_machine.host["avdtest-001"].secure_boot_enabled && azurerm_windows_virtual_machine.host["avdtest-001"].vtpm_enabled
    error_message = "Hosts are Trusted Launch."
  }

  assert {
    condition     = azurerm_windows_virtual_machine.host["avdtest-001"].license_type == "Windows_Client"
    error_message = "Multi-session hosts use Windows client licensing."
  }

  assert {
    condition     = azurerm_virtual_machine_extension.entra_join["avdtest-001"].settings == "{}"
    error_message = "No Intune enrollment unless asked."
  }

  assert {
    condition     = one(azurerm_virtual_machine_run_command.register_agent["avdtest-001"].protected_parameter).name == "RegistrationToken"
    error_message = "The registration token goes in as a protected parameter."
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
    condition     = azurerm_windows_virtual_machine.host["avdtest-001"].zone == null
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
    condition     = length(azurerm_windows_virtual_machine.host["avdtest-001"].source_image_reference) == 0
    error_message = "A gallery image replaces the marketplace reference."
  }
}

run "one_image_source_only" {
  command = plan

  variables {
    image_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Compute/galleries/gal_test/images/avd/versions/1.0.0"
  }

  expect_failures = [azurerm_windows_virtual_machine.host]
}

run "long_prefix_is_rejected" {
  command = plan

  variables {
    name_prefix = "much-too-long-prefix"
  }

  expect_failures = [var.name_prefix]
}
