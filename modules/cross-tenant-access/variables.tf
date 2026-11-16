variable "partner_tenant_id" {
  type        = string
  description = "Partner Microsoft Entra ID tenant UUID configured in Cross-Tenant Access Settings."
}

variable "b2b_inbound_access_type" {
  type        = string
  description = "Inbound B2B collaboration accessType for users/groups and applications (allowed or blocked)."
  default     = "allowed"

  validation {
    condition     = contains(["allowed", "blocked"], var.b2b_inbound_access_type)
    error_message = "b2b_inbound_access_type must be allowed or blocked."
  }
}

variable "b2b_outbound_access_type" {
  type        = string
  description = "Outbound B2B collaboration accessType for users/groups and applications (allowed or blocked)."
  default     = "allowed"

  validation {
    condition     = contains(["allowed", "blocked"], var.b2b_outbound_access_type)
    error_message = "b2b_outbound_access_type must be allowed or blocked."
  }
}

variable "trust_mfa" {
  type        = bool
  description = "Accept MFA claims from the partner Entra ID tenant (requires Entra ID P1 in partner/home tenant)."
  default     = false
}

variable "trust_compliant_device" {
  type        = bool
  description = "Accept compliant device claims from the partner Entra ID tenant."
  default     = false
}

variable "trust_hybrid_joined_device" {
  type        = bool
  description = "Accept Microsoft Entra hybrid joined device claims from the partner Entra ID tenant."
  default     = false
}

variable "allow_automatic_user_consent_inbound" {
  type        = bool
  description = "Allow automatic user consent for B2B inbound sync/apps."
  default     = false
}

variable "allow_automatic_user_consent_outbound" {
  type        = bool
  description = "Allow automatic user consent for B2B outbound sync/apps."
  default     = false
}
