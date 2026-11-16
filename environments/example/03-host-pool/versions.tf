terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
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
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  environment                     = var.cloud == "usgov" ? "usgovernment" : "public"
  storage_use_azuread             = true
  resource_provider_registrations = "none"
  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  environment     = var.cloud == "usgov" ? "usgovernment" : "public"
}

# Used only for ephemeral reads in modules/run-secrets.
provider "azapi" {
  alias           = "secrets"
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  environment     = var.cloud == "usgov" ? "usgovernment" : "public"
}
