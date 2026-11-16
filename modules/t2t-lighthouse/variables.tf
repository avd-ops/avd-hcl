variable "name" {
  type        = string
  description = "Display name of the Azure Lighthouse registration definition."
  default     = "avd-ops-t2t-lab"
}

variable "description" {
  type        = string
  description = "Description of the Azure Lighthouse delegation."
  default     = "Cross-tenant lab delegation for AVD T2T and Managed Services validation."
}

variable "managing_tenant_id" {
  type        = string
  description = "Microsoft Entra ID tenant UUID of the managing tenant (primary lab tenant)."
}

variable "target_subscription_id" {
  type        = string
  description = "Azure subscription UUID in the secondary tenant to delegate."
}

variable "authorizations" {
  type = list(object({
    principal_id                  = string
    principal_display_name        = string
    role_definition_id            = string
    delegated_role_definition_ids = optional(list(string), [])
  }))
  description = "List of managing-tenant principals and built-in role definition UUIDs granted via Lighthouse."

  validation {
    condition     = length(var.authorizations) > 0
    error_message = "Provide at least one authorization entry for Azure Lighthouse."
  }
}
