terraform {
  required_version = ">= 1.11"
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
  # State: local for the first plan and apply; then backend.tf, copied from backend.tf.example
  # (git-ignored), moves it to the state container. See docs/knowledge/github-settings-spec.md.
}

# The token comes from GITHUB_TOKEN in the environment, set for one process only: a short-lived
# fine-grained token for the first plan and apply, then a GitHub App token Key Vault signs for.
provider "github" {
  owner = "nickprignano"
}
