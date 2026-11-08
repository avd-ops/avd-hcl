# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), packer/avd-win11/variables.pkr.hcl; see CREDITS.md and NOTICE.
# Changes: default image definition is win11-24h2-avd-m365; no Ansible or Evergreen steps.

variable "subscription_id" {
  type        = string
  description = "Subscription that holds the build resource group and the Compute Gallery."
}

variable "tenant_id" {
  type        = string
  description = "Entra tenant for the build."
}

variable "use_azure_cli_auth" {
  type        = bool
  default     = true
  description = "Authenticate with the current az login. Set false and export ARM_CLIENT_ID / ARM_USE_OIDC for CI."
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "build_resource_group" {
  type        = string
  description = "Existing resource group Packer builds the temporary VM in (from environments/example/02-images)."
}

variable "build_subnet" {
  type = object({
    resource_group = string
    vnet           = string
    subnet         = string
  })
  default     = null
  description = "Build inside an existing subnet (no public IP). Null lets Packer create a temporary network with a public IP."
}

variable "vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "source_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "office-365"
    sku       = "win11-24h2-avd-m365"
    version   = "latest"
  }
  description = "Marketplace base image. The default is Windows 11 Enterprise multi-session with Microsoft 365 Apps."
}

variable "gallery" {
  type = object({
    resource_group   = string
    name             = string
    image_definition = string
    replica_regions  = list(string)
  })
  description = "Compute Gallery destination (from environments/example/02-images)."
}

variable "image_version" {
  type        = string
  default     = ""
  description = "Gallery image version (major.minor.patch). Empty uses YYYY.MMDD.hhmm."
}

variable "timezone" {
  type    = string
  default = "UTC"
}

variable "disconnected_session_hours" {
  type        = number
  default     = 8
  description = "Hours before a disconnected session is signed out, so a forgotten session cannot hold host rotation open indefinitely."
}

variable "run_windows_update" {
  type    = bool
  default = true
}

variable "wdot_profile" {
  type        = string
  default     = "avd-multisession"
  description = "Windows Desktop Optimization Tool profile from wdot.pkr.hcl: avd-multisession, minimal or none."

  validation {
    condition     = contains(["avd-multisession", "minimal", "none"], var.wdot_profile)
    error_message = "The wdot_profile must be avd-multisession, minimal or none."
  }
}

variable "wdot_overrides" {
  type        = map(map(string))
  default     = {}
  description = <<-EOT
    Per-setting WDOT changes on top of the profile, keyed by config file and then by setting name
    ("*" means every setting in that file). Values are Apply or Skip. Example:
    { Services = { SysMain = "Apply" }, AppxPackages = { "*" = "Apply", "Microsoft.WindowsCalculator" = "Skip" } }
  EOT

  validation {
    condition = alltrue([
      for f, settings in var.wdot_overrides : contains(
        ["AppxPackages", "Autologgers", "DefaultUserSettings", "EdgeSettings", "LanManWorkstation", "PolicyRegSettings", "ScheduledTasks", "Services"], f
      ) && alltrue([for v in values(settings) : contains(["Apply", "Skip"], v)])
    ])
    error_message = "The wdot_overrides keys must be WDOT config file names (Services, AppxPackages, ...) and every value must be Apply or Skip."
  }
}

variable "wdot_source" {
  type = object({
    repository = string
    commit     = string
  })
  default = {
    repository = "https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool"
    # main after v1.1: v1.1 itself passes -Source twice to New-EventLog on a fresh VM (fixed in 0c8d1e6).
    commit = "ff2574c016c6202dbb0303a3728016ad3dbf391c"
  }
  description = "Where the build host fetches WDOT. Pin a full commit SHA; point repository at an internal mirror on restricted networks."

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.wdot_source.commit))
    error_message = "The wdot_source.commit must be a full 40-character commit SHA."
  }
}

variable "gpu_preset" {
  type        = bool
  default     = false
  description = "Enable GPU hardware-accelerated frame encoding (AVC/HEVC) policies for GPU session hosts."
}

variable "tags" {
  type    = map(string)
  default = {}
}
