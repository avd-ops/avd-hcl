# Adapted from avd-landing-zone (MIT, commit 91c7acf), bicep/modules/sessionHosts.bicep; see
# CREDITS.md and NOTICE. Changes: written in Terraform with azurerm resources instead of the
# Azure Verified Module (decision 0003); each run command fails the apply when its script fails.
#
# Session hosts: Entra ID joined (optionally Intune enrolled), Trusted Launch, spread over the
# availability zones, monitored by the Azure Monitor agent, and made ready for users by two
# managed run commands, one after the other:
#   1. Configure-FSLogix (Entra Kerberos and the profile container)
#   2. Register-AvdAgent (agent, boot loader and registration token)
# Both scripts are in scripts/ and Terraform embeds them; nothing is downloaded at apply time.

locals {
  # 11-character prefix + "-" + 3 digits = 15 characters, the Windows computer name limit.
  hosts = {
    for i in range(var.host_count) : format("%s-%03d", var.name_prefix, i + 1) => {
      zone = length(var.availability_zones) == 0 ? null : var.availability_zones[i % length(var.availability_zones)]
    }
  }

  # Intune's well-known MDM application ID, the value the Entra join extension expects.
  intune_mdm_id = "0000000a-0000-0000-c000-000000000000"
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

resource "azurerm_windows_virtual_machine" "host" {
  for_each              = local.hosts
  name                  = each.key
  computer_name         = each.key
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  zone                  = each.value.zone
  network_interface_ids = [azurerm_network_interface.host[each.key].id]
  admin_username        = var.local_admin_username
  admin_password        = var.local_admin_password
  # AVD multi-session: Windows client licensing through the users' Microsoft 365 or Windows E3+ entitlement.
  license_type               = "Windows_Client"
  secure_boot_enabled        = true
  vtpm_enabled               = true
  encryption_at_host_enabled = var.encryption_at_host
  source_image_id            = var.image_id
  tags                       = var.tags

  dynamic "source_image_reference" {
    for_each = var.image_id == null ? [var.marketplace_image] : []
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  # Premium SSD: multi-session hosts page, sign in and update many users at once.
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {}

  lifecycle {
    # Azure applies the admin password only when a VM is created (avd-landing-zone lesson 0002),
    # so a new password in the vault must not rebuild the hosts.
    ignore_changes = [admin_password]

    precondition {
      condition     = (var.image_id == null) != (var.marketplace_image == null)
      error_message = "Set exactly one of image_id (a gallery image version) and marketplace_image."
    }
  }
}

# Extensions on one VM are written one at a time, so each kind waits for the one before it.
resource "azurerm_virtual_machine_extension" "entra_join" {
  for_each                   = local.hosts
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[each.key].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true
  settings                   = jsonencode(var.enroll_in_intune ? { mdmId = local.intune_mdm_id } : {})
  tags                       = var.tags
}

resource "azurerm_virtual_machine_extension" "monitor_agent" {
  for_each                   = local.hosts
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[each.key].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags

  depends_on = [azurerm_virtual_machine_extension.entra_join]
}

resource "azurerm_virtual_machine_extension" "guest_configuration" {
  for_each                   = local.hosts
  name                       = "AzurePolicyforWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[each.key].id
  publisher                  = "Microsoft.GuestConfiguration"
  type                       = "ConfigurationforWindows"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags

  depends_on = [azurerm_virtual_machine_extension.monitor_agent]
}

resource "azurerm_monitor_data_collection_rule_association" "avd_insights" {
  for_each                = local.hosts
  name                    = "avd-insights"
  target_resource_id      = azurerm_windows_virtual_machine.host[each.key].id
  data_collection_rule_id = var.data_collection_rule_id

  depends_on = [azurerm_virtual_machine_extension.monitor_agent]
}

resource "azurerm_virtual_machine_run_command" "configure_fslogix" {
  for_each           = local.hosts
  name               = "Configure-FSLogix"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.host[each.key].id
  tags               = var.tags

  source {
    script = file("${path.module}/scripts/Set-FSLogixConfiguration.ps1")
  }

  parameter {
    name  = "ProfileShareUncPath"
    value = var.profile_share_unc
  }

  parameter {
    name  = "ProfileSizeMiB"
    value = tostring(var.fslogix_profile_size_mib)
  }

  parameter {
    name  = "LocalAdminUsername"
    value = var.local_admin_username
  }

  lifecycle {
    postcondition {
      condition     = try(self.instance_view[0].exit_code, 0) == 0
      error_message = "Configure-FSLogix failed on the host; its output is in the run command's instance view."
    }
  }

  depends_on = [azurerm_virtual_machine_extension.guest_configuration]
}

resource "azurerm_virtual_machine_run_command" "register_agent" {
  for_each           = local.hosts
  name               = "Register-AvdAgent"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.host[each.key].id
  tags               = var.tags

  source {
    script = file("${path.module}/scripts/Register-AvdAgent.ps1")
  }

  protected_parameter {
    name  = "RegistrationToken"
    value = var.registration_token
  }

  lifecycle {
    # The token only matters when a host first registers. A new token on every apply would
    # rewrite the run command, and Azure refuses that on a deallocated host
    # (avd-landing-zone lesson 0026).
    ignore_changes = [protected_parameter]

    postcondition {
      condition     = try(self.instance_view[0].exit_code, 0) == 0
      error_message = "Register-AvdAgent failed on the host; its output is in the run command's instance view."
    }
  }

  # Run commands on one VM execute one at a time.
  depends_on = [azurerm_virtual_machine_run_command.configure_fslogix]
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
