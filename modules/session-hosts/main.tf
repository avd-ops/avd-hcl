# Adapted from avd-landing-zone (MIT, commit 91c7acf), bicep/modules/sessionHosts.bicep; see
# CREDITS.md and NOTICE. Changes: written in Terraform instead of the Azure Verified Module
# (decision 0003); each host gets its own break-glass password secret.
#
# Session hosts: Entra ID joined (optionally Intune enrolled), Trusted Launch, spread over the
# availability zones, monitored by the Azure Monitor agent, and made ready for users by two
# managed run commands, one after the other:
#   1. Configure-FSLogix (Entra Kerberos and the profile container)
#   2. Register-AvdAgent (agent, boot loader and registration token)
# Both scripts are in scripts/ and Terraform embeds them; nothing is downloaded at apply time.
#
# No secret is kept in state (guardrail 5). The VM, its password secret and the registration run
# command are written with azapi's write-only sensitive_body; the password is ephemeral and the
# registration token is read ephemerally. azurerm 5.10 has no write-only form for a VM's
# admin_password or a run command's protected parameters, which is why those three use azapi.
# The ephemeral values come from modules/run-secrets.
#
# Host settings reach existing hosts only by rebuilding them (host rotation, a later phase).
# Changing an extension or run command in place would fail on hosts that autoscale has
# deallocated (avd-landing-zone lesson 0026), so they ignore later changes.

locals {
  # 11-character prefix + "-" + 3 digits = 15 characters, the Windows computer name limit.
  hosts = {
    for i in range(var.host_count) : format("%s-%03d", var.name_prefix, i + 1) => {
      zone = length(var.availability_zones) == 0 ? null : var.availability_zones[i % length(var.availability_zones)]
    }
  }

  # Intune's well-known MDM application ID, the value the Entra join extension expects.
  intune_mdm_id = "0000000a-0000-0000-c000-000000000000"

  image_reference = var.image_id != null ? { id = var.image_id } : {
    publisher = var.marketplace_image.publisher
    offer     = var.marketplace_image.offer
    sku       = var.marketplace_image.sku
    version   = var.marketplace_image.version
  }
}

resource "azurerm_network_interface" "host" {
  for_each                       = local.hosts
  name                           = "${each.key}-nic"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = true
  tags                           = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azapi_resource" "host" {
  for_each  = local.hosts
  type      = "Microsoft.Compute/virtualMachines@2024-07-01"
  name      = each.key
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = merge(
    each.value.zone == null ? {} : { zones = [each.value.zone] },
    {
      properties = {
        hardwareProfile = { vmSize = var.vm_size }
        # AVD multi-session: Windows client licensing through the users' Microsoft 365 or Windows E3+ entitlement.
        licenseType = "Windows_Client"
        securityProfile = {
          securityType     = "TrustedLaunch"
          uefiSettings     = { secureBootEnabled = true, vTpmEnabled = true }
          encryptionAtHost = var.encryption_at_host
        }
        storageProfile = {
          imageReference = local.image_reference
          # Premium SSD: multi-session hosts page, sign in and update many users at once.
          osDisk = {
            name         = "${each.key}-osdisk"
            createOption = "FromImage"
            caching      = "ReadWrite"
            deleteOption = "Delete"
            managedDisk  = { storageAccountType = "Premium_LRS" }
          }
        }
        osProfile = {
          computerName  = each.key
          adminUsername = var.local_admin_username
          windowsConfiguration = {
            provisionVMAgent       = true
            enableAutomaticUpdates = true
          }
        }
        networkProfile = {
          networkInterfaces = [{ id = azurerm_network_interface.host[each.key].id, properties = { deleteOption = "Delete" } }]
        }
        diagnosticsProfile = { bootDiagnostics = { enabled = true } }
      }
    },
  )

  # Azure applies the admin password only when a VM is created (avd-landing-zone lesson 0002).
  sensitive_body = {
    properties = {
      osProfile = { adminPassword = var.local_admin_password }
    }
  }
  sensitive_body_version = {
    "properties.osProfile.adminPassword" = "1"
  }

  response_export_values = ["properties.vmId"]

  lifecycle {
    # A host's zone is fixed when it is created: changing availability_zones later places new
    # hosts only, instead of rebuilding running ones.
    ignore_changes = [body.zones]

    precondition {
      condition     = (var.image_id == null) != (var.marketplace_image == null)
      error_message = "Set exactly one of image_id (a gallery image version) and marketplace_image."
    }
  }
}

# One break-glass secret per host, written through ARM with the password the host was created
# with. If the write fails after the host is created, reset the host's password in the portal and
# store it here (avd-landing-zone lesson 0002).
resource "azapi_resource" "local_admin_password" {
  for_each  = local.hosts
  type      = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  name      = "${each.key}-localadmin"
  parent_id = var.key_vault_id
  body = {
    properties = {
      contentType = "password for ${var.local_admin_username}"
    }
  }
  sensitive_body = {
    properties = { value = var.local_admin_password }
  }
  sensitive_body_version = {
    "properties.value" = "1"
  }

  depends_on = [azapi_resource.host]
}

# Extensions on one VM are written one at a time, so each kind waits for the one before it.
resource "azurerm_virtual_machine_extension" "entra_join" {
  for_each                   = local.hosts
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azapi_resource.host[each.key].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true
  settings                   = jsonencode(var.enroll_in_intune ? { mdmId = local.intune_mdm_id } : {})
  tags                       = var.tags

  lifecycle {
    ignore_changes = [settings, tags]
  }
}

resource "azurerm_virtual_machine_extension" "monitor_agent" {
  for_each                   = local.hosts
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azapi_resource.host[each.key].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [azurerm_virtual_machine_extension.entra_join]
}

resource "azurerm_virtual_machine_extension" "guest_configuration" {
  for_each                   = local.hosts
  name                       = "AzurePolicyforWindows"
  virtual_machine_id         = azapi_resource.host[each.key].id
  publisher                  = "Microsoft.GuestConfiguration"
  type                       = "ConfigurationforWindows"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [azurerm_virtual_machine_extension.monitor_agent]
}

resource "azurerm_monitor_data_collection_rule_association" "avd_insights" {
  for_each                = local.hosts
  name                    = "avd-insights"
  target_resource_id      = azapi_resource.host[each.key].id
  data_collection_rule_id = var.data_collection_rule_id

  depends_on = [azurerm_virtual_machine_extension.monitor_agent]
}

# The run commands wait for their script (asyncExecution false), and a script that fails fails the
# apply (treatFailureAsDeploymentFailure), the same as the landing zone's Bicep.
resource "azapi_resource" "configure_fslogix" {
  for_each  = local.hosts
  type      = "Microsoft.Compute/virtualMachines/runCommands@2024-07-01"
  name      = "Configure-FSLogix"
  parent_id = azapi_resource.host[each.key].id
  location  = var.location
  tags      = var.tags

  body = {
    properties = {
      source = { script = file("${path.module}/scripts/Set-FSLogixConfiguration.ps1") }
      parameters = [
        { name = "ProfileShareUncPath", value = var.profile_share_unc },
        { name = "ProfileSizeMiB", value = tostring(var.fslogix_profile_size_mib) },
        { name = "LocalAdminUsername", value = var.local_admin_username },
      ]
      asyncExecution                  = false
      treatFailureAsDeploymentFailure = true
      timeoutInSeconds                = 600
    }
  }

  lifecycle {
    ignore_changes = [body, tags]
  }

  depends_on = [azurerm_virtual_machine_extension.guest_configuration]
}

resource "azapi_resource" "register_agent" {
  for_each  = local.hosts
  type      = "Microsoft.Compute/virtualMachines/runCommands@2024-07-01"
  name      = "Register-AvdAgent"
  parent_id = azapi_resource.host[each.key].id
  location  = var.location
  tags      = var.tags

  body = {
    properties = {
      source                          = { script = file("${path.module}/scripts/Register-AvdAgent.ps1") }
      asyncExecution                  = false
      treatFailureAsDeploymentFailure = true
      timeoutInSeconds                = 1800
    }
  }

  # The token only matters when a host first registers, so it is written once.
  sensitive_body = {
    properties = {
      protectedParameters = [
        { name = "RegistrationToken", value = var.registration_token },
      ]
    }
  }
  sensitive_body_version = {
    "properties.protectedParameters" = "1"
  }

  lifecycle {
    ignore_changes = [body, tags]
  }

  # Run commands on one VM execute one at a time.
  depends_on = [azapi_resource.configure_fslogix]
}

# ---------- Access to the hosts ----------
# Entra ID sign-in to the VMs needs these, in addition to the application group assignment.
resource "azurerm_role_assignment" "users_login" {
  for_each             = toset(var.user_group_object_ids)
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = each.value
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "admins_login" {
  for_each             = toset(var.admin_group_object_ids)
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = each.value
  principal_type       = "Group"
}
