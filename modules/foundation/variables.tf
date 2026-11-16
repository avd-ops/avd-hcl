# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/foundation; see CREDITS.md and NOTICE.

variable "location" {
  description = "Azure region for the resource groups."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource group."
  type        = map(string)
  default     = {}
}

variable "resource_groups" {
  description = <<-EOT
    Resource groups to create, keyed by role. The AVD control plane (host pool, application
    group, workspace, scaling plan) is kept apart from the session host VMs, so the VMs can be
    rebuilt without touching what users subscribe to.
  EOT
  type        = map(string)
  default = {
    network       = "rg-avd-network"
    control_plane = "rg-avd-control-plane"
    session_hosts = "rg-avd-session-hosts"
    storage       = "rg-avd-storage"
    monitoring    = "rg-avd-monitoring"
  }
  validation {
    condition     = alltrue([for k in ["network", "control_plane", "session_hosts", "storage", "monitoring"] : contains(keys(var.resource_groups), k)])
    error_message = "resource_groups must contain the keys network, control_plane, session_hosts, storage and monitoring."
  }
}

variable "existing_resource_group_names" {
  description = "Optional existing resource group names keyed by role (network, control_plane, session_hosts, storage, monitoring). Roles listed here are looked up instead of created."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for k in keys(var.existing_resource_group_names) : contains(["network", "control_plane", "session_hosts", "storage", "monitoring"], k)])
    error_message = "existing_resource_group_names keys must be from network, control_plane, session_hosts, storage and monitoring."
  }
}
