# Remote state in an Entra-authenticated storage account. The settings stay out of the repo:
# copy backend.hcl.example to backend.hcl (git-ignored) and run
#   terraform init -backend-config=backend.hcl
# The deploy pipeline passes the same settings itself (scripts/pipeline/stage.sh). State holds no
# password or token (they are ephemeral), but it maps the whole estate, so keep the account private.
terraform {
  backend "azurerm" {}
}
