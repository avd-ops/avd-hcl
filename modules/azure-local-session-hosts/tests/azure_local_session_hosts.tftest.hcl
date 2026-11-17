mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.HybridCompute/machines/avdtest-00"
    }
  }
}

variables {
  location               = "eastus2"
  resource_group_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
  name_prefix            = "avdtest"
  host_count             = 2
  custom_location_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hci/providers/Microsoft.ExtendedLocation/customLocations/cl-test"
  logical_network_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hci/providers/Microsoft.AzureStackHCI/logicalNetworks/lnet-avd"
  image_id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hci/providers/Microsoft.AzureStackHCI/galleryImages/win11-avd"
  local_admin_password   = "Placeholder-only-for-tests-1!"
  registration_token     = "placeholder-only-for-tests"
  local_smb_profile_path = "\\\\files01.contoso.com\\profiles"
  host_pool_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/vdpool-test"
}

run "deploys_azure_local_session_hosts" {
  command = plan

  assert {
    condition     = output.host_names == tolist(["avdtest-00", "avdtest-01"])
    error_message = "Hosts are named <prefix>-NN."
  }

  assert {
    condition     = azapi_resource.hybrid_machine["avdtest-00"].body.kind == "HCI"
    error_message = "HybridCompute machine must have kind HCI."
  }

  assert {
    condition     = azapi_resource.hybrid_machine["avdtest-00"].tags["cm-resource-parent"] == var.host_pool_resource_id
    error_message = "Host pool parent tag is attached when host_pool_resource_id is set."
  }

  assert {
    condition     = azapi_resource.hci_nic["avdtest-00"].body.extendedLocation.type == "CustomLocation" && azapi_resource.hci_nic["avdtest-00"].body.extendedLocation.name == var.custom_location_id
    error_message = "HCI NIC targets the Custom Location."
  }

  assert {
    condition     = azapi_resource.hci_nic["avdtest-00"].body.properties.ipConfigurations[0].properties.subnet.id == var.logical_network_id
    error_message = "HCI NIC binds to the Arc logical network."
  }

  assert {
    condition     = azapi_resource.vm_instance["avdtest-00"].body.properties.hardwareProfile.vmSize == "Custom" && azapi_resource.vm_instance["avdtest-00"].body.properties.hardwareProfile.processors == 4 && azapi_resource.vm_instance["avdtest-00"].body.properties.hardwareProfile.memoryMB == 16384
    error_message = "VM instance uses Custom vmSize with processors and memoryMB."
  }

  assert {
    condition     = !can(azapi_resource.vm_instance["avdtest-00"].body.properties.osProfile.adminPassword)
    error_message = "Admin password must only travel in write-only sensitive_body."
  }

  assert {
    condition     = azapi_resource.aad_login_extension["avdtest-00"].body.properties.type == "AADLoginForWindows" && azapi_resource.aad_login_extension["avdtest-00"].body.properties.settings.mdmId == "0000000a-0000-0000-c000-000000000000"
    error_message = "AADLoginForWindows passes Intune MDM ID when enroll_in_intune is true."
  }

  assert {
    condition     = !can(azapi_resource.avd_config_extension["avdtest-00"].body.properties.protectedSettings)
    error_message = "Registration token must only travel in write-only sensitive_body."
  }
}

run "no_intune_enrollment" {
  command = plan

  variables {
    host_count       = 1
    enroll_in_intune = false
  }

  assert {
    condition     = length(azapi_resource.aad_login_extension["avdtest-00"].body.properties.settings) == 0
    error_message = "AADLoginForWindows settings are empty when enroll_in_intune is false."
  }
}

run "zero_hosts" {
  command = plan

  variables {
    host_count = 0
  }

  assert {
    condition     = length(output.host_names) == 0 && length(output.vm_instance_ids) == 0 && length(output.hybrid_compute_machine_ids) == 0
    error_message = "Zero host_count produces empty outputs."
  }
}
