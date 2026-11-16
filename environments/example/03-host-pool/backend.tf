# Remote state in an Entra-authenticated storage account; pass -backend-config=backend.hcl at init.
terraform {
  backend "azurerm" {}
}
