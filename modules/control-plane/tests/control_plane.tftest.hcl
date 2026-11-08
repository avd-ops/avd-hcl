mock_provider "azurerm" {
  mock_resource "azurerm_virtual_desktop_host_pool" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.DesktopVirtualization/hostPools/vdpool-test"
    }
  }
  mock_resource "azurerm_virtual_desktop_application_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.DesktopVirtualization/applicationGroups/vdag-test"
    }
  }
  mock_resource "azurerm_virtual_desktop_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.DesktopVirtualization/workspaces/vdws-test"
    }
  }
  mock_resource "azurerm_virtual_desktop_scaling_plan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.DesktopVirtualization/scalingPlans/vdscaling-test"
    }
  }
}

mock_provider "time" {}
mock_provider "azapi" {}

variables {
  location                   = "eastus2"
  resource_group_name        = "rg-test"
  host_pool_name             = "vdpool-test"
  app_group_name             = "vdag-test"
  workspace_name             = "vdws-test"
  scaling_plan_name          = "vdscaling-test"
  user_group_object_ids      = ["00000000-0000-0000-0000-000000000001"]
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
}

run "pooled_desktop" {
  command = plan

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.type == "Pooled" && azurerm_virtual_desktop_host_pool.this.load_balancer_type == "BreadthFirst"
    error_message = "Expected a pooled, breadth-first host pool."
  }

  assert {
    condition     = strcontains(azurerm_virtual_desktop_host_pool.this.custom_rdp_properties, "targetisaadjoined:i:1")
    error_message = "Entra-joined hosts need targetisaadjoined:i:1 in the RDP properties."
  }

  assert {
    condition     = azurerm_role_assignment.desktop_users["00000000-0000-0000-0000-000000000001"].role_definition_name == "Desktop Virtualization User"
    error_message = "User groups get Desktop Virtualization User on the app group."
  }

  assert {
    condition     = azurerm_virtual_desktop_scaling_plan.this[0].exclusion_tag == "avd-scaling-exclude"
    error_message = "The scaling plan keeps the landing zone's exclusion tag."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 4
    error_message = "Host pool, app group, workspace and scaling plan all send logs."
  }
}

run "token_expiry_set_through_arm" {
  command = plan

  assert {
    condition     = azapi_update_resource.registration.body.properties.registrationInfo.registrationTokenOperation == "Update"
    error_message = "The token is issued through ARM so it never lands in state."
  }
}

run "no_scaling_plan" {
  command = plan

  variables {
    scaling_plan_enabled = false
  }

  assert {
    condition     = length(azurerm_virtual_desktop_scaling_plan.this) == 0 && length(azurerm_monitor_diagnostic_setting.this) == 3
    error_message = "No scaling plan, and logs from the other three objects."
  }
}

run "personal_desktop" {
  command = plan

  variables {
    host_pool_type = "Personal"
  }

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.type == "Personal" && azurerm_virtual_desktop_host_pool.this.load_balancer_type == "Persistent" && azurerm_virtual_desktop_host_pool.this.personal_desktop_assignment_type == "Automatic"
    error_message = "Personal pools use Persistent load balancing and Automatic assignment by default."
  }

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.start_vm_on_connect && azurerm_virtual_desktop_host_pool.this.maximum_sessions_allowed == null
    error_message = "Personal pools keep Start VM on Connect on and omit the pooled session limit."
  }

  assert {
    condition     = length(azurerm_virtual_desktop_scaling_plan.this) == 0 && length(azurerm_monitor_diagnostic_setting.this) == 3
    error_message = "Personal pools skip the pooled scaling plan."
  }
}
