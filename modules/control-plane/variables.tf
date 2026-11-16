variable "location" {
  description = "Azure region for the control plane objects (metadata only; hosts can be elsewhere)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the host pool, application group, workspace and scaling plan."
  type        = string
}


variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "host_pool_name" {
  description = "Host pool name."
  type        = string
}

variable "host_pool_friendly_name" {
  description = "Host pool display name."
  type        = string
  default     = null
}

variable "host_pool_type" {
  description = "Pooled (shared multi-session hosts) or Personal (one host per user, with Start VM on Connect)."
  type        = string
  default     = "Pooled"
  validation {
    condition     = contains(["Pooled", "Personal"], var.host_pool_type)
    error_message = "host_pool_type must be Pooled or Personal."
  }
}

variable "personal_assignment_type" {
  description = "How personal desktops are assigned when host_pool_type is Personal: Automatic (first available host on sign-in) or Direct."
  type        = string
  default     = "Automatic"
  validation {
    condition     = contains(["Automatic", "Direct"], var.personal_assignment_type)
    error_message = "personal_assignment_type must be Automatic or Direct."
  }
}

variable "app_group_name" {
  description = "Application group name."
  type        = string
}

variable "app_group_type" {
  description = "Application group type: Desktop (default) or RemoteApp."
  type        = string
  default     = "Desktop"
  validation {
    condition     = contains(["Desktop", "RemoteApp"], var.app_group_type)
    error_message = "app_group_type must be Desktop or RemoteApp."
  }
}

variable "desktop_display_name" {
  description = "Name users see on the desktop tile when app_group_type is Desktop."
  type        = string
  default     = "Desktop"
}

variable "remote_apps" {
  description = "Map of RemoteApp applications to publish when app_group_type is RemoteApp."
  type = map(object({
    friendly_name                = optional(string)
    description                  = optional(string)
    path                         = string
    command_line_argument_policy = optional(string, "DoNotAllow")
    command_line_arguments       = optional(string)
    show_in_portal               = optional(bool, true)
    icon_path                    = optional(string)
    icon_index                   = optional(number, 0)
  }))
  default = {}
}

variable "workspace_name" {
  description = "Workspace name. Required when existing_workspace_id is null."
  type        = string
  default     = null
}

variable "workspace_friendly_name" {
  description = "Workspace name users see in the Windows App feed."
  type        = string
  default     = null
}

variable "existing_workspace_id" {
  description = "Existing AVD workspace ID. When set, no new workspace is created and the desktop application group attaches to this workspace."
  type        = string
  default     = null
}

variable "scaling_plan_name" {
  description = "Scaling plan name."
  type        = string
}

variable "max_sessions_per_host" {
  description = "Most user sessions on one session host."
  type        = number
  default     = 8
  validation {
    condition     = var.max_sessions_per_host >= 1 && var.max_sessions_per_host <= 999999
    error_message = "max_sessions_per_host must be at least 1."
  }
}

variable "identity_model" {
  description = "Directory join model for the host pool's session hosts: entra_only (default), ad_ds, or entra_ds. Controls default RDP properties when rdp_properties is null."
  type        = string
  default     = "entra_only"
  validation {
    condition     = contains(["entra_only", "ad_ds", "entra_ds"], var.identity_model)
    error_message = "identity_model must be entra_only, ad_ds or entra_ds."
  }
}

variable "enable_private_link" {
  description = "Create AVD Private Link endpoints for the host pool (and workspace when created) and disable public network access."
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for AVD Private Link endpoints. Required when enable_private_link is true."
  type        = string
  default     = null
}

variable "private_dns_zone_id" {
  description = "privatelink.wvd.microsoft.com Private DNS zone ID. Required when enable_private_link is true."
  type        = string
  default     = null
}

variable "rdp_properties" {
  description = "Custom RDP properties for the host pool. Null selects the default for identity_model (Entra SSO for entra_only; no targetisaadjoined for ad_ds)."
  type        = string
  default     = null
}

variable "validation_environment" {
  description = "Make this a validation host pool, which gets AVD service updates first."
  type        = bool
  default     = false
}

variable "start_vm_on_connect" {
  description = "Start a deallocated session host when a user connects."
  type        = bool
  default     = true
}

variable "registration_token_hours" {
  description = "Registration token lifetime in hours (1 to 720). Short on purpose: it only has to outlive one apply."
  type        = number
  default     = 4
  validation {
    condition     = var.registration_token_hours >= 2 && var.registration_token_hours <= 720
    error_message = "registration_token_hours must be between 2 and 720."
  }
}

variable "scaling_plan_enabled" {
  description = "Deploy the autoscale plan."
  type        = bool
  default     = true
}

variable "time_zone" {
  description = "Windows time zone ID for the scaling plan schedules, for example \"Eastern Standard Time\"."
  type        = string
  default     = "UTC"
}

variable "scaling_exclusion_tag" {
  description = "VMs carrying this tag are left alone by autoscale."
  type        = string
  default     = "avd-scaling-exclude"
}

variable "user_group_object_ids" {
  description = "Entra groups of AVD users, granted Desktop Virtualization User on the desktop application group."
  type        = list(string)
  default     = []
}


variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for the control plane logs (AVD Insights reads them)."
  type        = string
}
