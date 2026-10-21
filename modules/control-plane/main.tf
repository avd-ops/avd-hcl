# Adapted from avd-landing-zone (MIT, commit 91c7acf), bicep/modules/controlPlane.bicep; see
# CREDITS.md and NOTICE. Changes: written in Terraform with azurerm resources instead of Azure
# Verified Modules (decision 0003); AVD Private Link comes in a later phase.
#
# Pooled host pool, desktop application group, workspace and an autoscale plan. Diagnostics from
# every object go to Log Analytics (that's what AVD Insights reads).

resource "azurerm_virtual_desktop_host_pool" "this" {
  name                     = var.host_pool_name
  friendly_name            = var.host_pool_friendly_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  preferred_app_group_type = "Desktop"
  maximum_sessions_allowed = var.max_sessions_per_host
  custom_rdp_properties    = var.rdp_properties
  validate_environment     = var.validation_environment
  start_vm_on_connect      = var.start_vm_on_connect
  public_network_access    = "Enabled"
  tags                     = var.tags

  scheduled_agent_updates {
    enabled                   = true
    use_session_host_timezone = true
    schedule {
      day_of_week = "Saturday"
      hour_of_day = 2
    }
  }
}

# A short-lived registration token. time_rotating is replaced once the token has expired, so the
# next apply after that issues a new one for any host it adds.
resource "time_rotating" "registration" {
  rotation_hours = var.registration_token_hours
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "this" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.this.id
  expiration_date = time_rotating.registration.rotation_rfc3339
}

resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                         = var.app_group_name
  friendly_name                = "Desktop"
  default_desktop_display_name = var.desktop_display_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  type                         = "Desktop"
  host_pool_id                 = azurerm_virtual_desktop_host_pool.this.id
  tags                         = var.tags
}

# The feed stays public so users can subscribe from any network.
resource "azurerm_virtual_desktop_workspace" "this" {
  name                          = var.workspace_name
  friendly_name                 = var.workspace_friendly_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "desktop" {
  workspace_id         = azurerm_virtual_desktop_workspace.this.id
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
  count               = var.scaling_plan_enabled ? 1 : 0
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
      workspace = azurerm_virtual_desktop_workspace.this.id
    },
    var.scaling_plan_enabled ? { scaling_plan = azurerm_virtual_desktop_scaling_plan.this[0].id } : {},
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
