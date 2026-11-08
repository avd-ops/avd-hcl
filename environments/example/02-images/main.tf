# The image stage: the Azure Compute Gallery, the Gen2 Trusted Launch image definition and the
# build resource group that packer/avd-win11 publishes golden images into.

locals {
  gallery_name = "gal_${replace(var.prefix, "-", "_")}_avd"

  tags = merge(var.tags, {
    environment = var.environment
    workload    = "avd"
    managed-by  = "terraform"
  })
}

resource "azurerm_resource_group" "images" {
  name     = "rg-${var.prefix}-images"
  location = var.location
  tags     = merge(local.tags, { "avd-kit-role" = "images" })
}

module "image_gallery" {
  source                    = "../../../modules/image-gallery"
  gallery_name              = local.gallery_name
  location                  = var.location
  resource_group_name       = azurerm_resource_group.images.name
  build_resource_group_name = "rg-${var.prefix}-images-build"
  packer_principal_id       = var.packer_principal_id
  tags                      = local.tags
}
