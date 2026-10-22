output "labels" {
  description = "The labels this module manages."
  value       = sort(keys(github_issue_label.this))
}

output "required_checks" {
  description = "The checks the ruleset requires (empty list while the ruleset is off)."
  value       = var.enforce_ruleset ? local.required_checks : []
}

output "ruleset_id" {
  description = "The ruleset's ID, for its import block after the first apply. Null while the ruleset is off."
  value       = var.enforce_ruleset ? github_repository_ruleset.main[0].ruleset_id : null
}
