# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/image-gallery; see CREDITS.md and NOTICE.

terraform {
  required_version = ">= 1.11"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
  }
}
