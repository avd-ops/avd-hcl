# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/github-repo/main.tf; see CREDITS.md.
# Changes: merge settings, security, topics, required checks and the conventions' labels added.
# Repository settings as code: one repository, every setting the conventions name, nothing else.
# Spec: docs/knowledge/github-settings-spec.md. GitHub environments belong to the deploy pipeline,
# never to this module.

locals {
  # Labels from avd-second-brain decisions 0013 (no-kb), 0014 (handoff, handoff-proposed, same colors
  # as the kb-freshness workflow) and 0015 (no-auto-merge); drift is the drift check's label.
  labels = merge({
    "no-kb"            = { color = "e4e669", description = "Code change with no knowledge base entry; the PR body says why" }
    "no-auto-merge"    = { color = "d93f0b", description = "Keep this pull request for the owner" }
    "handoff"          = { color = "0052cc", description = "Owner-approved handoff from another project (decision 0014)" }
    "handoff-proposed" = { color = "c5def5", description = "Handoff a project proposed; waits for the owner" }
    "drift"            = { color = "fbca04", description = "GitHub settings differ from github/ (drift check)" }
  }, var.extra_labels)

  required_checks = var.kb_auto_merge ? concat(var.required_checks, ["auto-merge"]) : var.required_checks

  # GitHub Actions' app ID, a public constant: required checks must come from Actions, not from
  # any app that posts a status with the same name.
  github_actions_app_id = 15368

  # Repository admin role, a public constant used for the ruleset's bypass list.
  repository_admin_role_id = 5
}

resource "github_repository" "this" {
  name        = var.repository
  description = var.description
  visibility  = var.visibility
  topics      = var.topics

  # The provider's defaults differ from GitHub's (has_issues defaults to false), so every
  # argument that has a default is set here; the module test checks the list.
  has_issues      = true
  has_wiki        = false
  has_projects    = false
  has_discussions = false
  is_template     = false
  homepage_url    = ""
  archived        = false

  allow_merge_commit     = true
  allow_squash_merge     = false
  allow_rebase_merge     = false
  allow_auto_merge       = var.kb_auto_merge
  allow_update_branch    = false
  delete_branch_on_merge = true
  merge_commit_title     = "MERGE_MESSAGE"
  merge_commit_message   = "PR_TITLE"

  web_commit_signoff_required = false

  dynamic "security_and_analysis" {
    for_each = var.visibility == "public" ? [1] : []
    content {
      secret_scanning {
        status = "enabled"
      }
      secret_scanning_push_protection {
        status = "enabled"
      }
    }
  }

  # A destroy of this resource deletes the repository. Neither a typo nor terraform destroy may
  # do that; retire this setup with removed blocks instead.
  archive_on_destroy = true
  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}

# Security updates need the alerts on first.
resource "github_repository_dependabot_security_updates" "this" {
  repository = github_repository.this.name
  enabled    = true
  depends_on = [github_repository_vulnerability_alerts.this]
}

# Every workflow declares its own permissions, so the default token stays read-only, and Actions
# can't approve pull requests.
resource "github_workflow_repository_permissions" "this" {
  repository                       = github_repository.this.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

# One resource per label: labels not listed here are left alone.
resource "github_issue_label" "this" {
  for_each    = local.labels
  repository  = github_repository.this.name
  name        = each.key
  color       = each.value.color
  description = each.value.description
}

resource "github_repository_ruleset" "main" {
  count       = var.enforce_ruleset ? 1 : 0
  name        = "main"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # The owner can still merge a pull request whose checks never ran (decision 0015, section 3).
  bypass_actors {
    actor_id    = local.repository_admin_role_id
    actor_type  = "RepositoryRole"
    bypass_mode = "pull_request"
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      # The owner can't approve their own pull requests.
      required_approving_review_count = 0
      allowed_merge_methods           = ["merge"]
    }

    required_status_checks {
      strict_required_status_checks_policy = false

      dynamic "required_check" {
        for_each = local.required_checks
        content {
          context        = required_check.value
          integration_id = local.github_actions_app_id
        }
      }
    }
  }
}
