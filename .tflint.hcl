# tflint settings for every module and root (CI runs it in each folder with --chdir).
# The azurerm ruleset checks values Terraform can't, such as VM sizes and storage names.
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# prevent_destroy can't vary by environment, and every sandbox run must tear down right after
# (CLAUDE.md). Data is kept by soft delete, versioning and share retention instead.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
