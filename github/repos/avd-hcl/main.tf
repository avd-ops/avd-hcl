# This repository's GitHub settings. The conventions live in the module; only what differs for
# this repository is set here. Applies run only from Cloud Shell, by the owner (spec section 8).

module "settings" {
  source = "../../modules/repo-settings"

  repository  = "avd-hcl"
  visibility  = "private"
  description = "Native Azure Virtual Desktop with Terraform and Packer"
  topics      = ["azure-virtual-desktop", "terraform", "packer", "azure", "infrastructure-as-code"]

  # The CI job display names after PR #10 merges. A renamed job is a settings change: update
  # this list in the same pull request.
  required_checks = ["Terraform", "Parameter schema", "Guard", "gitleaks"]

  # Off until the owner is on GitHub Pro or the repository is public (spec, Q2).
  enforce_ruleset = false
}

output "ruleset_id" {
  description = "Add an import block with this ID after the first apply that creates the ruleset."
  value       = module.settings.ruleset_id
}
