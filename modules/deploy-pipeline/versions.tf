# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/deploy-pipeline/versions.tf; see CREDITS.md and NOTICE.

terraform {
  required_version = ">= 1.11"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.3"
    }
  }
}
