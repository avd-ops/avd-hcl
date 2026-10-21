# Adapted from avd-landing-zone (MIT, commit 91c7acf), bicep/modules/monitoring.bicep; see
# CREDITS.md and NOTICE. Changes: written in Terraform; the alert rules and action group come
# in a later phase.

resource "azurerm_log_analytics_workspace" "avd" {
  name                         = var.name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  sku                          = "PerGB2018"
  retention_in_days            = var.retention_in_days
  local_authentication_enabled = false
  tags                         = var.tags
}

# AVD Insights only recognizes data collection rules whose name starts with "microsoft-avdi-".
# Counters and event logs follow the Microsoft-published AVD Insights set.
resource "azurerm_monitor_data_collection_rule" "avd_insights" {
  name                = "microsoft-avdi-${var.prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Windows"
  description         = "AVD Insights performance counters and event logs."
  tags                = var.tags

  destinations {
    log_analytics {
      name                  = "law"
      workspace_resource_id = azurerm_log_analytics_workspace.avd.id
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Event"]
    destinations = ["law"]
  }

  data_sources {
    performance_counter {
      name                          = "perfCounters30s"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 30
      counter_specifiers = [
        "\\LogicalDisk(C:)\\Avg. Disk Queue Length",
        "\\LogicalDisk(C:)\\Current Disk Queue Length",
        "\\Memory\\Available Mbytes",
        "\\Memory\\Page Faults/sec",
        "\\Memory\\Pages/sec",
        "\\Memory\\% Committed Bytes In Use",
        "\\PhysicalDisk(*)\\Avg. Disk Queue Length",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Read",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Transfer",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Write",
        "\\Processor Information(_Total)\\% Processor Time",
        "\\User Input Delay per Process(*)\\Max Input Delay",
        "\\User Input Delay per Session(*)\\Max Input Delay",
        "\\RemoteFX Network(*)\\Current TCP RTT",
        "\\RemoteFX Network(*)\\Current UDP Bandwidth",
      ]
    }

    performance_counter {
      name                          = "perfCounters60s"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\LogicalDisk(C:)\\% Free Space",
        "\\LogicalDisk(C:)\\Avg. Disk sec/Transfer",
        "\\Terminal Services(*)\\Active Sessions",
        "\\Terminal Services(*)\\Inactive Sessions",
        "\\Terminal Services(*)\\Total Sessions",
      ]
    }

    windows_event_log {
      name    = "avdEventLogs"
      streams = ["Microsoft-Event"]
      x_path_queries = [
        "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
        "System!*",
        "Microsoft-FSLogix-Apps/Operational!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Application!*[System[(Level=2 or Level=3)]]",
        "Microsoft-FSLogix-Apps/Admin!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
      ]
    }
  }
}
