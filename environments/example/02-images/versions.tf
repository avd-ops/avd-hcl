terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
  }
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.Compute",
    "Microsoft.Network",
    "Microsoft.Storage",
  ]

  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
