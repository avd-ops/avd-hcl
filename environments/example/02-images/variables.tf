# Every required variable here is answered through schema/parameters.json.

variable "tenant_id" {
  description = "Entra tenant ID. Read from the signed-in account, never asked or saved."
  type        = string
}

variable "subscription_id" {
  description = "Subscription to deploy into. Read from the signed-in account, never asked or saved."
  type        = string
}

variable "environment" {
  description = "sandbox, dev or prod. Sets the environment tag."
  type        = string
  default     = "sandbox"
  validation {
    condition     = contains(["sandbox", "dev", "prod"], var.environment)
    error_message = "environment must be sandbox, dev or prod."
  }
}

variable "location" {
  description = "Azure region for the Compute Gallery and Packer build resource group."
  type        = string
}

variable "prefix" {
  description = "Naming prefix: 2-13 lowercase letters, digits or hyphens, for example avd-dev."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.prefix)) && length(var.prefix) >= 2 && length(var.prefix) <= 13
    error_message = "prefix must be 2-13 lowercase letters, digits or single hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "tags" {
  description = "Extra tags on every resource."
  type        = map(string)
  default     = {}
}

variable "packer_principal_id" {
  description = "Object ID of the identity that runs Packer. Null skips the role assignments."
  type        = string
  default     = null
}
