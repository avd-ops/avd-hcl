# Adapted from avd-landing-zone (MIT, commit 91c7acf), bicep/modules/keyVault.bicep; see
# CREDITS.md and NOTICE. Changes: written in Terraform, and the secrets go through ARM (azapi).
#
# Holds the session hosts' break-glass local admin credential, so nobody has to remember it
# (avd-landing-zone lesson 0002): the username here, and one password secret per host, written
# by modules/session-hosts when it creates the host. RBAC-authorized, purge-protected, reachable only over its
# private endpoint. The secrets are written through the management plane (ARM), not the vault's
# data plane: a runner outside the VNet can't reach a vault with public access disabled, but ARM
# can still create secrets in it.

locals {
  use_existing_vault = var.existing_key_vault_id != null
  key_vault_id       = local.use_existing_vault ? var.existing_key_vault_id : azurerm_key_vault.this[0].id
  key_vault_name     = local.use_existing_vault ? element(split("/", var.existing_key_vault_id), length(split("/", var.existing_key_vault_id)) - 1) : azurerm_key_vault.this[0].name
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  count                         = local.use_existing_vault ? 0 : 1
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  lifecycle {
    precondition {
      condition     = var.private_endpoint_subnet_id != null && var.private_dns_zone_id != null && var.log_analytics_workspace_id != null
      error_message = "private_endpoint_subnet_id, private_dns_zone_id and log_analytics_workspace_id are required when creating a new Key Vault."
    }
  }
}

resource "azurerm_private_endpoint" "vault" {
  count               = local.use_existing_vault ? 0 : 1
  name                = "pe-${var.name}-vault"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "vault"
    private_connection_resource_id = azurerm_key_vault.this[0].id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azapi_resource_action" "local_admin_username" {
  type        = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  resource_id = "${local.key_vault_id}/secrets/sessionhost-localadmin-username"
  method      = "PUT"
  body = {
    properties = {
      value = var.local_admin_username
    }
  }
}

resource "azurerm_role_assignment" "admins_read_secrets" {
  for_each             = toset(var.admin_group_object_ids)
  scope                = local.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
  principal_type       = "Group"
}

resource "azurerm_monitor_diagnostic_setting" "vault" {
  count                      = local.use_existing_vault ? 0 : 1
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_key_vault.this[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }
}
