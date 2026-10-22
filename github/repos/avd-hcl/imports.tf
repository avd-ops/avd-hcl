# Every object that already exists is imported, so the first plan shows a real diff only where the
# repository has drifted from the conventions. Objects created by the first apply (the labels,
# later the ruleset) get their import blocks in a follow-up pull request, so a fresh state can
# always be rebuilt from GitHub.

import {
  to = module.settings.github_repository.this
  id = "avd-hcl"
}

import {
  to = module.settings.github_repository_vulnerability_alerts.this
  id = "avd-hcl"
}

import {
  to = module.settings.github_repository_dependabot_security_updates.this
  id = "avd-hcl"
}

import {
  to = module.settings.github_workflow_repository_permissions.this
  id = "avd-hcl"
}
