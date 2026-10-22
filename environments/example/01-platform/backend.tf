# Remote state in an Entra-authenticated storage account. The settings stay out of the repo:
# copy backend.hcl.example to backend.hcl (git-ignored) and run
#   terraform init -backend-config=backend.hcl
# State holds the hosts' admin password and the registration token, so keep the account private.
terraform {
  backend "azurerm" {}
}
