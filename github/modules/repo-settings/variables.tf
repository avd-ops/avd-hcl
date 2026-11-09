# Only what differs between repositories is an input. The conventions themselves are locals in
# main.tf, each with its source in ../../conventions.md.

variable "repository" {
  description = "Repository name, without the owner (the provider's owner sets the account)."
  type        = string
}

variable "visibility" {
  description = "private or public. Secret scanning and push protection are set only on a public repository, because GitHub doesn't offer them on a personal account's private repositories."
  type        = string
  validation {
    condition     = contains(["private", "public"], var.visibility)
    error_message = "visibility is private or public."
  }
}

variable "description" {
  description = "The repository's one-line description."
  type        = string
}

variable "topics" {
  description = "Repository topics."
  type        = list(string)
  default     = []
}

variable "required_checks" {
  description = "Status checks the ruleset requires on main: the display names of CI jobs that report on every pull request. A check that never reports holds every pull request (decision 0015, section 3)."
  type        = list(string)
  validation {
    condition     = length(var.required_checks) > 0
    error_message = "List at least one required check."
  }
}

variable "enforce_ruleset" {
  description = "Create the ruleset on main. Rulesets on a personal account's private repository need GitHub Pro, so this stays false until the owner upgrades or the repository goes public."
  type        = bool
  default     = false
}

variable "kb_auto_merge" {
  description = "Turn on 'Allow auto-merge' and require the kb-auto-merge workflow's auto-merge check, together, as decision 0015 section 3 requires. Only once that workflow is installed here."
  type        = bool
  default     = false
  validation {
    # Without the ruleset nothing would require the check, and an armed pull request would merge
    # with nothing gating it.
    condition     = !var.kb_auto_merge || var.enforce_ruleset
    error_message = "kb_auto_merge needs enforce_ruleset: auto-merge only with the ruleset that requires the auto-merge check."
  }
}

variable "extra_labels" {
  description = "Labels this repository needs beyond the conventions' labels, by name."
  type = map(object({
    color       = string
    description = string
  }))
  default = {}
}
