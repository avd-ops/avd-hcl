# Adapted from avd-landing-zone (MIT, commit 91c7acf), bicep/modules/controlPlane.bicep; see
# CREDITS.md and NOTICE. Changes: written in Terraform with azurerm resources instead of Azure
# Verified Modules (decision 0003); AVD Private Link comes in a later phase.
#
# Pooled or personal host pool, desktop application group, workspace and an autoscale plan.
# Diagnostics from every object go to Log Analytics (that's what AVD Insights reads).

locals {
  use_existing_workspace = var.existing_workspace_id != null
  deploy_scaling_plan    = var.scaling_plan_enabled && var.host_pool_type == "Pooled"
  base_rdp_properties    = "drivestoredirect:s:;usbdevicestoredirect:s:;redirectcomports:i:0;redirectsmartcards:i:1;redirectprinters:i:1;redirectclipboard:i:1;redirectwebauthn:i:1;audiomode:i:0;audiocapturemode:i:1;camerastoredirect:s:*;use multimon:i:1"
  effective_rdp_properties = var.rdp_properties != null ? var.rdp_properties : (
    var.identity_model == "entra_only" ? "enablerdsaadauth:i:1;targetisaadjoined:i:1;${local.base_rdp_properties}" : local.base_rdp_properties
  )
}

resource "azurerm_virtual_desktop_host_pool" "this" {
  name                             = var.host_pool_name
  friendly_name                    = var.host_pool_friendly_name
  location                         = var.location
  resource_group_name              = var.resource_group_name
  type                             = var.host_pool_type
  load_balancer_type               = var.host_pool_type == "Personal" ? "Persistent" : "BreadthFirst"
  personal_desktop_assignment_type = var.host_pool_type == "Personal" ? var.personal_assignment_type : null
  preferred_app_group_type         = var.app_group_type == "RemoteApp" ? "RailApplications" : "Desktop"
  maximum_sessions_allowed         = var.host_pool_type == "Personal" ? null : var.max_sessions_per_host
  custom_rdp_properties            = local.effective_rdp_properties
  validate_environment             = var.validation_environment
  start_vm_on_connect              = var.start_vm_on_connect
  public_network_access            = var.enable_private_link ? "Disabled" : "Enabled"
  tags                             = var.tags

  scheduled_agent_updates {
    enabled                   = true
    timezone                  = var.time_zone
    use_session_host_timezone = false
    schedule {
      day_of_week = "Saturday"
      hour_of_day = 2
    }
  }
}

# A short-lived registration token. The expiry is set on the host pool through ARM, and the token
# itself is only ever read ephemerally (modules/session-hosts), so it is never kept in state
# (guardrail 5). azurerm_virtual_desktop_host_pool_registration_info would store it.
# time_rotating is replaced once the token has expired, so the next apply after that issues a new
# one for any host it adds.
resource "time_rotating" "registration" {
  rotation_hours = var.registration_token_hours
}

resource "azapi_update_resource" "registration" {
  type        = "Microsoft.DesktopVirtualization/hostPools@2024-04-03"
  resource_id = azurerm_virtual_desktop_host_pool.this.id
  body = {
    properties = {
      registrationInfo = {
        expirationTime             = time_rotating.registration.rotation_rfc3339
        registrationTokenOperation = "Update"
      }
    }
  }
}

resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                         = var.app_group_name
  friendly_name                = var.app_group_type
  default_desktop_display_name = var.app_group_type == "Desktop" ? var.desktop_display_name : null
  location                     = var.location
  resource_group_name          = var.resource_group_name
  type                         = var.app_group_type
  host_pool_id                 = azurerm_virtual_desktop_host_pool.this.id
  tags                         = var.tags
}

resource "azurerm_virtual_desktop_application" "this" {
  for_each                     = var.app_group_type == "RemoteApp" ? var.remote_apps : {}
  name                         = each.key
  application_group_id         = azurerm_virtual_desktop_application_group.desktop.id
  friendly_name                = coalesce(each.value.friendly_name, each.key)
  description                  = each.value.description
  path                         = each.value.path
  command_line_argument_policy = each.value.command_line_argument_policy
  command_line_arguments       = each.value.command_line_arguments
  show_in_portal               = each.value.show_in_portal
  icon_path                    = coalesce(each.value.icon_path, each.value.path)
  icon_index                   = each.value.icon_index
}

# The feed stays public unless Private Link is enabled.
resource "azurerm_virtual_desktop_workspace" "this" {
  count                         = local.use_existing_workspace ? 0 : 1
  name                          = var.workspace_name
  friendly_name                 = var.workspace_friendly_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  public_network_access_enabled = !var.enable_private_link
  tags                          = var.tags

  lifecycle {
    precondition {
      condition     = var.workspace_name != null
      error_message = "workspace_name is required when existing_workspace_id is null."
    }
  }
}

resource "azurerm_private_endpoint" "host_pool" {
  count               = var.enable_private_link ? 1 : 0
  name                = "pe-${var.host_pool_name}-connection"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "connection"
    private_connection_resource_id = azurerm_virtual_desktop_host_pool.this.id
    subresource_names              = ["connection"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }

  lifecycle {
    precondition {
      condition     = var.private_endpoint_subnet_id != null && var.private_dns_zone_id != null
      error_message = "enable_private_link requires private_endpoint_subnet_id and private_dns_zone_id."
    }
  }
}

resource "azurerm_private_endpoint" "workspace" {
  count               = var.enable_private_link && !local.use_existing_workspace ? 1 : 0
  name                = "pe-${var.workspace_name}-feed"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "feed"
    private_connection_resource_id = azurerm_virtual_desktop_workspace.this[0].id
    subresource_names              = ["feed"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

locals {
  workspace_id = local.use_existing_workspace ? var.existing_workspace_id : azurerm_virtual_desktop_workspace.this[0].id
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "desktop" {
  workspace_id         = local.workspace_id
  application_group_id = azurerm_virtual_desktop_application_group.desktop.id
}

resource "azurerm_role_assignment" "desktop_users" {
  for_each             = toset(var.user_group_object_ids)
  scope                = azurerm_virtual_desktop_application_group.desktop.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = each.value
  principal_type       = "Group"
}


# Autoscale acts as the AVD service principal, which needs Desktop Virtualization Power On Off
# Contributor at subscription scope before the plan is created. The root module grants it.
# Weekdays: ramp up 07:00, peak 09:00, ramp down 18:00, off-peak 20:00.
# Weekends: off-peak most of the day; Start VM on Connect brings a host up on demand.
resource "azurerm_virtual_desktop_scaling_plan" "this" {
  count               = local.deploy_scaling_plan ? 1 : 0
  name                = var.scaling_plan_name
  location            = var.location
  resource_group_name = var.resource_group_name
  time_zone           = var.time_zone
  exclusion_tag       = var.scaling_exclusion_tag
  tags                = var.tags

  schedule {
    name                                 = "weekdays"
    days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    ramp_up_start_time                   = "07:00"
    ramp_up_load_balancing_algorithm     = "BreadthFirst"
    ramp_up_minimum_hosts_percent        = 20
    ramp_up_capacity_threshold_percent   = 60
    peak_start_time                      = "09:00"
    peak_load_balancing_algorithm        = "BreadthFirst"
    ramp_down_start_time                 = "18:00"
    ramp_down_load_balancing_algorithm   = "DepthFirst"
    ramp_down_minimum_hosts_percent      = 10
    ramp_down_capacity_threshold_percent = 90
    ramp_down_force_logoff_users         = false
    ramp_down_wait_time_minutes          = 30
    ramp_down_notification_message       = "This session host is being shut down to save cost. Please save your work and sign out."
    ramp_down_stop_hosts_when            = "ZeroSessions"
    off_peak_start_time                  = "20:00"
    off_peak_load_balancing_algorithm    = "DepthFirst"
  }

  schedule {
    name                                 = "weekends"
    days_of_week                         = ["Saturday", "Sunday"]
    ramp_up_start_time                   = "09:00"
    ramp_up_load_balancing_algorithm     = "DepthFirst"
    ramp_up_minimum_hosts_percent        = 0
    ramp_up_capacity_threshold_percent   = 90
    peak_start_time                      = "10:00"
    peak_load_balancing_algorithm        = "DepthFirst"
    ramp_down_start_time                 = "16:00"
    ramp_down_load_balancing_algorithm   = "DepthFirst"
    ramp_down_minimum_hosts_percent      = 0
    ramp_down_capacity_threshold_percent = 90
    ramp_down_force_logoff_users         = false
    ramp_down_wait_time_minutes          = 30
    ramp_down_notification_message       = "This session host is being shut down to save cost. Please save your work and sign out."
    ramp_down_stop_hosts_when            = "ZeroSessions"
    off_peak_start_time                  = "18:00"
    off_peak_load_balancing_algorithm    = "DepthFirst"
  }

  host_pool {
    hostpool_id          = azurerm_virtual_desktop_host_pool.this.id
    scaling_plan_enabled = true
  }
}

locals {
  diagnostics = merge(
    {
      host_pool = azurerm_virtual_desktop_host_pool.this.id
      app_group = azurerm_virtual_desktop_application_group.desktop.id
    },
    local.use_existing_workspace ? {} : { workspace = azurerm_virtual_desktop_workspace.this[0].id },
    local.deploy_scaling_plan ? { scaling_plan = azurerm_virtual_desktop_scaling_plan.this[0].id } : {},
  )
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each                   = local.diagnostics
  name                       = "to-log-analytics"
  target_resource_id         = each.value
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}
