# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/image-gallery; see CREDITS.md and NOTICE.
# Changes: native AVD description and principal_type on role assignments.

resource "azurerm_shared_image_gallery" "this" {
  name                = var.gallery_name
  location            = var.location
  resource_group_name = var.resource_group_name
  description         = "AVD golden images built by Packer"
  tags                = var.tags
}

# Gen2 + Trusted Launch to match the session hosts and the Packer build.
resource "azurerm_shared_image" "this" {
  for_each                            = var.image_definitions
  name                                = each.key
  gallery_name                        = azurerm_shared_image_gallery.this.name
  location                            = var.location
  resource_group_name                 = var.resource_group_name
  os_type                             = "Windows"
  hyper_v_generation                  = "V2"
  trusted_launch_supported            = true
  accelerated_network_support_enabled = each.value.accelerated_network_support_enabled
  hibernation_enabled                 = each.value.hibernation_enabled
  tags                                = var.tags

  identifier {
    publisher = each.value.publisher
    offer     = each.value.offer
    sku       = each.value.sku
  }
}

resource "azurerm_resource_group" "build" {
  name     = var.build_resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_role_assignment" "packer_gallery" {
  count                = var.packer_principal_id == null ? 0 : 1
  scope                = azurerm_shared_image_gallery.this.id
  role_definition_name = "Contributor"
  principal_id         = var.packer_principal_id
}

resource "azurerm_role_assignment" "packer_build" {
  count                = var.packer_principal_id == null ? 0 : 1
  scope                = azurerm_resource_group.build.id
  role_definition_name = "Contributor"
  principal_id         = var.packer_principal_id
}
