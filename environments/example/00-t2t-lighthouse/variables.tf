variable "target_tenant_id" {
  type        = string
  description = "Secondary Microsoft Entra ID tenant UUID owning target_subscription_id."
}

variable "target_subscription_id" {
  type        = string
  description = "Azure subscription UUID (t2t-lab) in the secondary tenant to prepare and delegate."
}

variable "managing_tenant_id" {
  type        = string
  description = "Primary lab Microsoft Entra ID tenant UUID granted Azure Lighthouse access."
}

variable "name" {
  type        = string
  description = "Display name of the Azure Lighthouse registration definition."
  default     = "avd-ops-t2t-lab"
}

variable "authorizations" {
  type = list(object({
    principal_id                  = string
    principal_display_name        = string
    role_definition_id            = string
    delegated_role_definition_ids = optional(list(string), [])
  }))
  description = "Managing-tenant principals and built-in role definition UUIDs granted via Lighthouse."
}
