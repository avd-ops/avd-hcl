# Offline: a mock provider, no token, no network.

mock_provider "github" {
  mock_resource "github_repository_ruleset" {
    defaults = {
      ruleset_id = 1
    }
  }
}

variables {
  repository      = "contoso-kit"
  visibility      = "private"
  description     = "Example"
  topics          = ["terraform"]
  required_checks = ["Terraform", "Guard"]
}

run "private_defaults" {
  command = plan

  # Arguments whose provider default differs from GitHub's are all set (spec section 4).
  assert {
    condition     = github_repository.this.has_issues == true
    error_message = "Issues must stay on; the provider's default would turn them off."
  }
  assert {
    condition = alltrue([
      github_repository.this.has_wiki == false,
      github_repository.this.has_projects == false,
      github_repository.this.has_discussions == false,
      github_repository.this.is_template == false,
      github_repository.this.archived == false,
      github_repository.this.homepage_url == "",
      github_repository.this.allow_update_branch == false,
      github_repository.this.web_commit_signoff_required == false,
    ])
    error_message = "Every argument with a provider default is set explicitly."
  }
  assert {
    condition = alltrue([
      github_repository.this.allow_merge_commit == true,
      github_repository.this.allow_squash_merge == false,
      github_repository.this.allow_rebase_merge == false,
      github_repository.this.delete_branch_on_merge == true,
      github_repository.this.merge_commit_title == "MERGE_MESSAGE",
      github_repository.this.merge_commit_message == "PR_TITLE",
    ])
    error_message = "Merge settings follow the conventions (merge commits only)."
  }
  assert {
    condition     = github_repository.this.allow_auto_merge == false
    error_message = "Auto-merge stays off without the kb-auto-merge workflow."
  }
  assert {
    condition     = github_repository_vulnerability_alerts.this.enabled == true && github_repository_dependabot_security_updates.this.enabled == true
    error_message = "Dependabot alerts and security updates are on."
  }
  assert {
    condition     = length(github_repository.this.security_and_analysis) == 0
    error_message = "A private personal repository can't set secret scanning; the block must be absent."
  }
  assert {
    condition     = github_repository.this.archive_on_destroy == true
    error_message = "A destroy must archive, never delete."
  }
  assert {
    condition     = github_workflow_repository_permissions.this.default_workflow_permissions == "read" && github_workflow_repository_permissions.this.can_approve_pull_request_reviews == false
    error_message = "The default workflow token is read-only and can't approve pull requests."
  }
  assert {
    condition     = toset(keys(github_issue_label.this)) == toset(["no-kb", "no-auto-merge", "handoff", "handoff-proposed", "drift"])
    error_message = "The conventions' labels are managed."
  }
  assert {
    condition     = length(github_repository_ruleset.main) == 0
    error_message = "No ruleset until enforce_ruleset is set."
  }
}

run "public_with_ruleset" {
  command = plan

  variables {
    visibility      = "public"
    enforce_ruleset = true
  }

  assert {
    condition     = github_repository.this.security_and_analysis[0].secret_scanning[0].status == "enabled" && github_repository.this.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled"
    error_message = "A public repository gets secret scanning and push protection."
  }
  assert {
    condition     = github_repository_ruleset.main[0].enforcement == "active" && github_repository_ruleset.main[0].conditions[0].ref_name[0].include == tolist(["~DEFAULT_BRANCH"])
    error_message = "The ruleset is active on the default branch."
  }
  assert {
    condition     = github_repository_ruleset.main[0].rules[0].deletion && github_repository_ruleset.main[0].rules[0].non_fast_forward
    error_message = "main can't be deleted or force-pushed."
  }
  assert {
    condition     = github_repository_ruleset.main[0].rules[0].pull_request[0].required_approving_review_count == 0
    error_message = "No required review: the owner can't approve their own pull requests."
  }
  assert {
    condition     = toset([for c in github_repository_ruleset.main[0].rules[0].required_status_checks[0].required_check : c.context]) == toset(["Terraform", "Guard"])
    error_message = "The required checks are the ones given, and only those."
  }
  assert {
    condition     = alltrue([for c in github_repository_ruleset.main[0].rules[0].required_status_checks[0].required_check : c.integration_id == 15368])
    error_message = "Required checks must come from GitHub Actions."
  }
  assert {
    condition     = github_repository_ruleset.main[0].bypass_actors[0].actor_type == "RepositoryRole" && github_repository_ruleset.main[0].bypass_actors[0].bypass_mode == "pull_request"
    error_message = "Admins bypass for pull requests only."
  }
}

run "kb_auto_merge_switch" {
  command = plan

  variables {
    enforce_ruleset = true
    kb_auto_merge   = true
  }

  assert {
    condition     = github_repository.this.allow_auto_merge == true
    error_message = "kb_auto_merge turns on Allow auto-merge."
  }
  assert {
    condition     = contains([for c in github_repository_ruleset.main[0].rules[0].required_status_checks[0].required_check : c.context], "auto-merge")
    error_message = "kb_auto_merge also requires the auto-merge check (decision 0015, section 3)."
  }
}

run "no_required_checks_refused" {
  command = plan

  variables {
    required_checks = []
  }

  expect_failures = [var.required_checks]
}

run "kb_auto_merge_needs_the_ruleset" {
  command = plan

  variables {
    kb_auto_merge = true
  }

  expect_failures = [var.kb_auto_merge]
}
