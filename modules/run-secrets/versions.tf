terraform {
  required_version = ">= 1.11"
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
      # Its own provider configuration, so a plan-only test can mock every other azapi call
      # while this one stays a real provider: mock providers can't hold ephemeral resources.
      configuration_aliases = [azapi.secrets]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
