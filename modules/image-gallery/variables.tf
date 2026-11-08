# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/image-gallery; see CREDITS.md and NOTICE.
# Changes: default image definition is win11-24h2-avd-m365, and gallery name validation matches Azure's rule.

variable "gallery_name" {
  description = "Azure Compute Gallery name (letters, digits, underscores and periods; cannot start or end with a period or underscore)."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._]{0,78}[a-zA-Z0-9]$", var.gallery_name))
    error_message = "gallery_name must be 2-80 letters, digits, underscores or periods, starting and ending with a letter or digit."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the Compute Gallery."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "image_definitions" {
  description = "Image definitions Packer publishes into, keyed by definition name."
  type = map(object({
    publisher                           = string
    offer                               = string
    sku                                 = string
    accelerated_network_support_enabled = optional(bool, true)
    hibernation_enabled                 = optional(bool, false)
  }))
  default = {
    "win11-24h2-avd-m365" = {
      publisher                           = "AVD"
      offer                               = "Windows11-MultiSession"
      sku                                 = "24h2-m365"
      accelerated_network_support_enabled = true
      hibernation_enabled                 = false
    }
  }
}

variable "packer_principal_id" {
  description = "Object ID of the identity that runs Packer. Gets Contributor on the gallery and build resource group. Null skips the role assignments."
  type        = string
  default     = null
}

variable "build_resource_group_name" {
  description = "Resource group Packer builds temporary VMs in. Created here so Packer needs no subscription-wide create rights."
  type        = string
}
