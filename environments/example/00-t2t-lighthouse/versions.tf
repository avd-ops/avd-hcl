# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

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
  subscription_id                 = var.target_subscription_id
  tenant_id                       = var.target_tenant_id
  resource_provider_registrations = "none"
  features {}
}
