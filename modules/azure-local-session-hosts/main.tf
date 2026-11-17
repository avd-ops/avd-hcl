# Azure Local session hosts — native Entra ID join only in v1 (Decision 0023),
# deployed as Arc-enabled virtual machine instances on an existing registered
# Azure Local 23H2+ instance with a Custom Location and Arc logical network.
#
# Matches avd-azure/bicep/modules/azureLocalSessionHosts.bicep. Secrets
# (local_admin_password and registration_token) travel only in azapi
# write-only sensitive_body so nothing secret is stored in state.

locals {
  hosts = {
    for i in range(var.host_count) : format("%s-%02d", var.name_prefix, i) => i
  }

  host_tags = var.host_pool_resource_id != "" ? merge(var.tags, {
    "cm-resource-parent" = var.host_pool_resource_id
  }) : var.tags

  # Intune's well-known MDM application ID, the value AADLoginForWindows expects.
  intune_mdm_id = "0000000a-0000-0000-c000-000000000000"

  fslogix_cmd = var.local_smb_profile_path != "" ? "New-Item -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Force | Out-Null; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name Enabled -Value 1 -Type DWord; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name VHDLocations -Value '${var.local_smb_profile_path}' -Type MultiString; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name SizeInMBs -Value ${var.fslogix_profile_size_mib} -Type DWord;" : ""
}

resource "azapi_resource" "hybrid_machine" {
  for_each  = local.hosts
  type      = "Microsoft.HybridCompute/machines@2024-07-10"
  name      = each.key
  parent_id = var.resource_group_id
  location  = var.location
  tags      = local.host_tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "HCI"
  }
}

resource "azapi_resource" "hci_nic" {
  for_each  = local.hosts
  type      = "Microsoft.AzureStackHCI/networkInterfaces@2024-01-01"
  name      = "${each.key}-nic"
  parent_id = var.resource_group_id
  location  = var.location
  tags      = local.host_tags

  body = {
    extendedLocation = {
      type = "CustomLocation"
      name = var.custom_location_id
    }
    properties = {
      ipConfigurations = [
        {
          name = "ipconfig1"
          properties = {
            subnet = {
              id = var.logical_network_id
            }
          }
        }
      ]
    }
  }
}

resource "azapi_resource" "vm_instance" {
  for_each  = local.hosts
  type      = "Microsoft.AzureStackHCI/virtualMachineInstances@2024-01-01"
  name      = "default"
  parent_id = azapi_resource.hybrid_machine[each.key].id

  body = {
    extendedLocation = {
      type = "CustomLocation"
      name = var.custom_location_id
    }
    properties = {
      hardwareProfile = {
        vmSize     = "Custom"
        processors = var.processors
        memoryMB   = var.memory_mb
      }
      osProfile = {
        computerName  = each.key
        adminUsername = var.local_admin_username
        windowsConfiguration = {
          provisionVMAgent       = true
          provisionVMConfigAgent = true
        }
      }
      networkProfile = {
        networkInterfaces = [
          {
            id = azapi_resource.hci_nic[each.key].id
          }
        ]
      }
      storageProfile = {
        imageReference = {
          id = var.image_id
        }
      }
    }
  }

  sensitive_body = {
    properties = {
      osProfile = {
        adminPassword = var.local_admin_password
      }
    }
  }
  sensitive_body_version = {
    "properties.osProfile.adminPassword" = "1"
  }
}

resource "azapi_resource" "aad_login_extension" {
  for_each   = local.hosts
  type       = "Microsoft.HybridCompute/machines/extensions@2024-07-10"
  name       = "AADLoginForWindows"
  parent_id  = azapi_resource.hybrid_machine[each.key].id
  location   = var.location
  tags       = local.host_tags
  depends_on = [azapi_resource.vm_instance]

  body = {
    properties = {
      publisher               = "Microsoft.Azure.ActiveDirectory"
      type                    = "AADLoginForWindows"
      autoUpgradeMinorVersion = true
      settings = var.enroll_in_intune ? {
        mdmId = local.intune_mdm_id
      } : {}
    }
  }
}

resource "azapi_resource" "avd_config_extension" {
  for_each   = local.hosts
  type       = "Microsoft.HybridCompute/machines/extensions@2024-07-10"
  name       = "ConfigureAvdAndFSLogix"
  parent_id  = azapi_resource.hybrid_machine[each.key].id
  location   = var.location
  tags       = local.host_tags
  depends_on = [azapi_resource.aad_login_extension]

  body = {
    properties = {
      publisher               = "Microsoft.Compute"
      type                    = "CustomScriptExtension"
      autoUpgradeMinorVersion = true
    }
  }

  sensitive_body = {
    properties = {
      protectedSettings = {
        commandToExecute = "powershell -ExecutionPolicy Bypass -Command \"${local.fslogix_cmd} New-Item -Path 'HKLM:\\SOFTWARE\\Microsoft\\RDInfraAgent' -Force | Out-Null; Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\RDInfraAgent' -Name RegistrationToken -Value '${var.registration_token}' -Type String\""
      }
    }
  }
  sensitive_body_version = {
    "properties.protectedSettings.commandToExecute" = "1"
  }
}
