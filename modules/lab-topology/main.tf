locals {
  base_subscription_specs = {
    "platform-connectivity" = {
      mg_key   = "platform-connectivity"
      workload = "Production"
    }
    "platform-management" = {
      mg_key   = "platform-management"
      workload = "Production"
    }
    "lz-avd-workload" = {
      mg_key   = "landing-zones"
      workload = "DevTest"
    }
    "sandbox-ci" = {
      mg_key   = "sandbox"
      workload = "DevTest"
    }
  }

  second_workload_spec = var.enable_second_workload_spoke || contains(keys(var.existing_subscription_ids), "lz-avd-workload-2") ? {
    "lz-avd-workload-2" = {
      mg_key   = "landing-zones"
      workload = "DevTest"
    }
  } : {}

  subscription_specs = merge(local.base_subscription_specs, local.second_workload_spec)

  subscriptions_to_vend = var.vend_subscriptions ? {
    for k, v in local.subscription_specs : k => v if !contains(keys(var.existing_subscription_ids), k)
  } : {}

  active_subscription_ids = merge(
    var.existing_subscription_ids,
    { for k, sub in azurerm_subscription.vended : k => sub.subscription_id }
  )
}

resource "azurerm_management_group" "platform" {
  name                       = "${var.prefix}-platform"
  display_name               = "platform"
  parent_management_group_id = var.root_management_group_id
}

resource "azurerm_management_group" "platform_connectivity" {
  name                       = "${var.prefix}-platform-connectivity"
  display_name               = "connectivity"
  parent_management_group_id = azurerm_management_group.platform.id
}

resource "azurerm_management_group" "platform_management" {
  name                       = "${var.prefix}-platform-management"
  display_name               = "management"
  parent_management_group_id = azurerm_management_group.platform.id
}

resource "azurerm_management_group" "landing_zones" {
  name                       = "${var.prefix}-landing-zones"
  display_name               = "landing-zones"
  parent_management_group_id = var.root_management_group_id
}

resource "azurerm_management_group" "sandbox" {
  name                       = "${var.prefix}-sandbox"
  display_name               = "sandbox"
  parent_management_group_id = var.root_management_group_id
}

resource "azurerm_management_group" "decommissioned" {
  name                       = "${var.prefix}-decommissioned"
  display_name               = "decommissioned"
  parent_management_group_id = var.root_management_group_id
}

locals {
  management_groups = {
    "platform"              = azurerm_management_group.platform.id
    "platform-connectivity" = azurerm_management_group.platform_connectivity.id
    "platform-management"   = azurerm_management_group.platform_management.id
    "landing-zones"         = azurerm_management_group.landing_zones.id
    "sandbox"               = azurerm_management_group.sandbox.id
    "decommissioned"        = azurerm_management_group.decommissioned.id
  }
}

resource "azurerm_subscription" "vended" {
  for_each = local.subscriptions_to_vend

  subscription_name = "${var.prefix}-${each.key}"
  alias             = "${var.prefix}-${each.key}"
  billing_scope_id  = var.billing_scope_id
  workload          = each.value.workload
  tags              = var.tags
}

resource "azurerm_management_group_subscription_association" "lab" {
  for_each = local.active_subscription_ids

  management_group_id = local.management_groups[local.subscription_specs[each.key].mg_key]
  subscription_id     = "/subscriptions/${each.value}"
}

resource "azurerm_consumption_budget_subscription" "lab" {
  for_each = local.active_subscription_ids

  name            = "${var.prefix}-${each.key}-monthly"
  subscription_id = "/subscriptions/${each.value}"

  amount     = var.monthly_budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Forecasted"
    contact_emails = var.budget_alert_emails
  }
}

resource "azurerm_role_assignment" "ci_sandbox_contributor" {
  count = var.ci_principal_id != null ? 1 : 0

  scope                = azurerm_management_group.sandbox.id
  role_definition_name = "Contributor"
  principal_id         = var.ci_principal_id
}
