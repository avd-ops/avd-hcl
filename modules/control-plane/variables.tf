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

variable "app_group_name" {
  description = "Desktop application group name."
  type        = string
}

variable "desktop_display_name" {
  description = "Name users see on the desktop tile."
  type        = string
  default     = "Desktop"
}

variable "workspace_name" {
  description = "Workspace name."
  type        = string
}

variable "workspace_friendly_name" {
  description = "Workspace name users see in the Windows App feed."
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

variable "rdp_properties" {
  description = "Custom RDP properties for the host pool. The default is the landing zone's: Entra single sign-on, no drive, USB or COM redirection."
  type        = string
  default     = "enablerdsaadauth:i:1;targetisaadjoined:i:1;drivestoredirect:s:;usbdevicestoredirect:s:;redirectcomports:i:0;redirectsmartcards:i:1;redirectprinters:i:1;redirectclipboard:i:1;redirectwebauthn:i:1;audiomode:i:0;audiocapturemode:i:1;camerastoredirect:s:*;use multimon:i:1"
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
