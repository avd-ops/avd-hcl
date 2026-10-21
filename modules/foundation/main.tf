# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/foundation; see CREDITS.md and NOTICE.
# Changes: resource groups are the AVD roles of this kit, the Log Analytics workspace moved to
# modules/monitoring, and the provider-registration cleanup block is gone (this kit never had it).

# Resource providers are registered by the azurerm provider block in the root module
# (resource_providers_to_register), which skips any already registered.

resource "azurerm_resource_group" "this" {
  for_each = var.resource_groups
  name     = each.value
  location = var.location
  tags     = merge(var.tags, { "avd-kit-role" = each.key })
}
