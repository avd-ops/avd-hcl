# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), environments/example/00-pipeline/versions.tf; see CREDITS.md and NOTICE.

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

  # No backend here: scripts/pipeline/bootstrap.sh writes backend_override.tf (git-ignored) for the
  # chosen environment, local state first, then the storage account this stage creates.
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.Storage", "Microsoft.ManagedIdentity"]
  storage_use_azuread             = true
}

provider "azuread" {
  tenant_id = var.tenant_id
}

# Reads GITHUB_TOKEN from the environment. The bootstrap script passes `gh auth token` to this
# one terraform process only; it's never written to a file.
provider "github" {
  owner = var.github.owner
}
