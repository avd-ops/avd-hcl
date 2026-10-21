variable "location" {
  description = "Azure region for the session hosts."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the session host VMs."
  type        = string
}

variable "resource_group_id" {
  description = "ID of the same resource group, where the sign-in roles are granted."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "host_count" {
  description = "Number of session hosts."
  type        = number
  default     = 1
  validation {
    condition     = var.host_count >= 0 && var.host_count <= 999 && floor(var.host_count) == var.host_count
    error_message = "host_count must be a whole number from 0 to 999."
  }
}

variable "name_prefix" {
  description = "VM name prefix, up to 11 characters; hosts are named <prefix>-001, <prefix>-002 and so on."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,10}$", var.name_prefix))
    error_message = "name_prefix must be 1-11 letters, digits or hyphens, starting with a letter (Windows names stop at 15 characters)."
  }
}

variable "vm_size" {
  description = "Session host VM size. Memory-optimized E-series suits multi-session hosts."
  type        = string
  default     = "Standard_E4as_v5"
}

variable "availability_zones" {
  description = "Zones to spread new hosts over, round robin. Empty for a region without zones. An existing host keeps its zone."
  type        = list(string)
  default     = []
}

variable "marketplace_image" {
  description = "Marketplace image for the hosts. Set to null when image_id is set."
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
}

variable "image_id" {
  description = "Azure Compute Gallery image version ID from the image pipeline. A version, never a definition, so nothing changes software silently."
  type        = string
  default     = null
}

variable "encryption_at_host" {
  description = "Encrypt temp disks and caches at the host. Needs the EncryptionAtHost feature registered on the subscription."
  type        = bool
  default     = true
}

variable "subnet_id" {
  description = "Session host subnet."
  type        = string
}

variable "enroll_in_intune" {
  description = "Enroll the hosts in Intune when they join Entra ID."
  type        = bool
  default     = false
}

variable "local_admin_username" {
  description = "Break-glass local admin username."
  type        = string
  default     = "avdbreakglass"
}

variable "local_admin_password" {
  description = "Break-glass local admin password for hosts created in this run, generated ephemerally by the root module. Each host's copy goes to Key Vault as <host>-localadmin."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "key_vault_id" {
  description = "Key Vault for the per-host break-glass secrets."
  type        = string
}

variable "registration_token" {
  description = "Host pool registration token, read ephemerally by modules/run-secrets. Written once, to each new host's registration run command."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "data_collection_rule_id" {
  description = "AVD Insights data collection rule."
  type        = string
}

variable "profile_share_unc" {
  description = "FSLogix profile share, as \\\\account.file.core.windows.net\\share."
  type        = string
}

variable "fslogix_profile_size_mib" {
  description = "Largest a profile container may grow, in MiB."
  type        = number
  default     = 30720
}

variable "user_group_object_ids" {
  description = "Entra groups of AVD users, granted Virtual Machine User Login on the hosts."
  type        = list(string)
  default     = []
}

variable "admin_group_object_ids" {
  description = "Entra groups of host admins, granted Virtual Machine Administrator Login."
  type        = list(string)
  default     = []
}
