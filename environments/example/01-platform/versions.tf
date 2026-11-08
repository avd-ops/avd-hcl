# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), environments/example/01-platform/versions.tf;
# see CREDITS.md and NOTICE. Changes: the providers and resource providers AVD itself needs, and
# the azurerm features this kit relies on.

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
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }

  # State settings: backend.tf and backend.hcl.example.
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  # The profile account has shared key access off, so data-plane calls use Entra ID.
  storage_use_azuread = true
  # Register only the providers AVD and the kit need. The provider does this when it starts and
  # skips any already registered.
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.Compute",
    "Microsoft.Consumption",
    "Microsoft.DesktopVirtualization",
    "Microsoft.DevTestLab",
    "Microsoft.GuestConfiguration",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
  ]

  features {
    key_vault {
      # Purge protection keeps a deleted vault for 90 days; adopt it instead of failing on its name
      # (avd-landing-zone lesson 0022).
      recover_soft_deleted_key_vaults = true
      purge_soft_delete_on_destroy    = false
    }
    log_analytics_workspace {
      # A soft-deleted workspace comes back without its tables, and the AVD Insights rule then
      # fails with InvalidOutputTable (avd-landing-zone lesson 0023).
      permanently_delete_on_destroy = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# The same identity, used only for the ephemeral reads in modules/run-secrets.
provider "azapi" {
  alias           = "secrets"
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
