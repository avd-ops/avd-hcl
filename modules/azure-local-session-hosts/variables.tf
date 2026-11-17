variable "location" {
  description = "Azure region matching the Azure Local cluster registration."
  type        = string
}

variable "resource_group_id" {
  description = "Resource group ID where the Arc machine and logical NIC resources are placed."
  type        = string
}

variable "tags" {
  description = "Tags applied to Arc machine, NIC, and extension resources."
  type        = map(string)
  default     = {}
}

variable "host_count" {
  description = "Number of Azure Local session hosts to deploy."
  type        = number
  default     = 1
  validation {
    condition     = var.host_count >= 0 && var.host_count <= 999 && floor(var.host_count) == var.host_count
    error_message = "host_count must be a whole number from 0 to 999."
  }
}

variable "name_prefix" {
  description = "Host name prefix, up to 11 characters so <prefix>-NN fits the 15-character NetBIOS limit."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,10}$", var.name_prefix))
    error_message = "name_prefix must be 1-11 letters, digits or hyphens, starting with a letter."
  }
}

variable "custom_location_id" {
  description = "Resource ID of the target Custom Location (Microsoft.ExtendedLocation/customLocations)."
  type        = string
}

variable "logical_network_id" {
  description = "Resource ID of the target Arc logical network (Microsoft.AzureStackHCI/logicalNetworks)."
  type        = string
}

variable "image_id" {
  description = "Resource ID of the target Azure Local gallery or marketplace image."
  type        = string
}

variable "processors" {
  description = "vCPU count per Azure Local VM instance."
  type        = number
  default     = 4
  validation {
    condition     = var.processors >= 2 && floor(var.processors) == var.processors
    error_message = "processors must be a whole number of at least 2."
  }
}

variable "memory_mb" {
  description = "Memory in MB per Azure Local VM instance."
  type        = number
  default     = 16384
  validation {
    condition     = var.memory_mb >= 4096 && floor(var.memory_mb) == var.memory_mb
    error_message = "memory_mb must be a whole number of at least 4096."
  }
}

variable "enroll_in_intune" {
  description = "Enroll native Entra-joined session hosts in Microsoft Intune."
  type        = bool
  default     = true
}

variable "local_admin_username" {
  description = "Local administrator username for VM provisioning."
  type        = string
  default     = "avdbreakglass"
}

variable "local_admin_password" {
  description = "Local administrator password for VM provisioning, passed ephemerally via write-only sensitive_body."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "registration_token" {
  description = "AVD host pool registration token, passed ephemerally via write-only sensitive_body."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "local_smb_profile_path" {
  description = "Bring-your-own on-premises SMB UNC path for FSLogix profile containers."
  type        = string
  default     = ""
}

variable "fslogix_profile_size_mib" {
  description = "FSLogix profile VHDX max size in MiB."
  type        = number
  default     = 30720
}

variable "host_pool_resource_id" {
  description = "Resource ID of the parent AVD host pool (applied as cm-resource-parent tag when non-empty)."
  type        = string
  default     = ""
}
