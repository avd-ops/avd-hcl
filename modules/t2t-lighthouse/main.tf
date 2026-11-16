locals {
  scope = "/subscriptions/${var.target_subscription_id}"
}

resource "azurerm_lighthouse_definition" "this" {
  name               = var.name
  description        = var.description
  managing_tenant_id = var.managing_tenant_id
  scope              = local.scope

  dynamic "authorization" {
    for_each = var.authorizations
    content {
      principal_id                  = authorization.value.principal_id
      principal_display_name        = authorization.value.principal_display_name
      role_definition_id            = authorization.value.role_definition_id
      delegated_role_definition_ids = length(authorization.value.delegated_role_definition_ids) > 0 ? authorization.value.delegated_role_definition_ids : null
    }
  }
}

resource "azurerm_lighthouse_assignment" "this" {
  scope                    = local.scope
  lighthouse_definition_id = azurerm_lighthouse_definition.this.id
}
