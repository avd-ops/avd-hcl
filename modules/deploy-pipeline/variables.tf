# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/deploy-pipeline/variables.tf; see CREDITS.md and NOTICE.
# Changes: the roles the AVD platform stage assigns, read-only Graph roles, the private-repository
# gate check, and the name rule follows the platform prefix so the storage name always fits.

variable "name" {
  description = "Short name used in every resource name, for example avd-sbx. One per environment."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) >= 2 && length(var.name) <= 13
    error_message = "Use 2 to 13 lowercase letters and digits, with single hyphens between them, starting with a letter."
  }
}

variable "location" {
  description = "Azure region for the state storage and the deploy identities."
  type        = string
}

variable "subscription_id" {
  description = "Subscription the pipeline deploys into. Its roles are scoped here."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant of the subscription."
  type        = string
}

variable "environment" {
  description = "Kit environment name, such as sandbox, dev or prod. The GitHub environments are <environment>-plan and <environment>-apply."
  type        = string
  default     = "sandbox"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.environment))
    error_message = "Use lowercase letters, digits or hyphens."
  }
}

variable "github" {
  description = <<-EOT
    The repository the pipeline runs from. reviewers are the GitHub logins allowed to approve an
    apply; at least one is required. branch is the only branch that can use either environment,
    so a pull request branch can never get a token for this subscription. Set enterprise only on
    GitHub Enterprise, where a private repository's environments enforce reviewers too.
  EOT
  type = object({
    owner      = string
    repository = string
    reviewers  = list(string)
    branch     = optional(string, "main")
    enterprise = optional(bool, false)
  })

  validation {
    condition     = length(var.github.reviewers) > 0
    error_message = "Name at least one reviewer; an apply must always need a person's approval."
  }
}

variable "plan_graph_roles" {
  description = "Microsoft Graph application roles for the plan identity. Read-only: Terraform looks up the AVD service principal, and the answers name groups that are looked up before the plan."
  type        = list(string)
  nullable    = false # null (from the stage) means this default
  default     = ["Application.Read.All", "Group.Read.All"]
}

variable "apply_graph_roles" {
  description = <<-EOT
    Microsoft Graph application roles for the apply identity. The platform stage creates no Entra
    objects: it only reads the AVD service principal, so read-only is enough. Keep these
    read-only; a write role here would let an approved run widen its own access.
  EOT
  type        = list(string)
  nullable    = false # null (from the stage) means this default
  default     = ["Application.Read.All"]

  validation {
    condition     = length([for r in var.apply_graph_roles : r if strcontains(r, "ReadWrite")]) == 0
    error_message = "The apply identity's Graph roles stay read-only; grant a write role to a person through PIM instead."
  }
}

variable "apply_roles" {
  description = "Azure roles for the apply identity on the subscription. The platform stage creates role assignments, so it needs Role Based Access Control Administrator alongside Contributor."
  type        = list(string)
  nullable    = false # null (from the stage) means this default
  default     = ["Contributor", "Role Based Access Control Administrator"]
}

variable "apply_assignable_roles" {
  description = <<-EOT
    The only roles the apply identity may assign or remove. Azure enforces it with a role
    assignment condition on Role Based Access Control Administrator (or User Access
    Administrator), so the identity can't grant Owner or any role the kit doesn't use. These are
    the roles the platform stage assigns; add one here in the pull request that adds its
    assignment.
  EOT
  type        = list(string)
  nullable    = false # null (from the stage) means this default
  default = [
    "Desktop Virtualization User",
    "Desktop Virtualization Power On Off Contributor",
    "Virtual Machine User Login",
    "Virtual Machine Administrator Login",
    "Key Vault Secrets User",
    "Storage File Data SMB Share Contributor",
    "Storage File Data SMB Share Elevated Contributor",
  ]

  validation {
    condition     = length(var.apply_assignable_roles) > 0
    error_message = "List at least one role; an empty list would drop the condition."
  }

  validation {
    condition     = length(setintersection(var.apply_assignable_roles, ["Owner", "User Access Administrator", "Role Based Access Control Administrator"])) == 0
    error_message = "The apply identity must not be able to hand out Owner or the role-assignment administrator roles."
  }
}

variable "plan_reads_registration_token" {
  description = "Let the plan identity read host pool registration tokens, which Terraform needs while it plans session hosts. Off means plans fail once a host pool exists and host_count > 0."
  type        = bool
  default     = true
}

variable "storage_replication" {
  description = "Replication for the state storage account. ZRS where the region has zones; LRS otherwise."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.storage_replication)
    error_message = "Use LRS, ZRS, GRS or GZRS."
  }
}

variable "plan_retention_days" {
  description = "Days to keep saved plans. They hold the values Terraform will apply, so they don't linger."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags for every Azure resource."
  type        = map(string)
  default     = {}
}
