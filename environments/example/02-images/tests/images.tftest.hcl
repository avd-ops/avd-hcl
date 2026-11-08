mock_provider "azurerm" {
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test-images"
    }
  }
  mock_resource "azurerm_shared_image_gallery" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test-images/providers/Microsoft.Compute/galleries/gal_avd_test_avd"
    }
  }
}

variables {
  tenant_id       = "00000000-0000-0000-0000-000000000001"
  subscription_id = "00000000-0000-0000-0000-000000000000"
  location        = "eastus2"
  prefix          = "avd-test"
}

run "gallery_and_build_rg" {
  command = plan

  assert {
    condition     = output.gallery_name == "gal_avd_test_avd" && output.gallery_resource_group_name == "rg-avd-test-images" && output.build_resource_group_name == "rg-avd-test-images-build"
    error_message = "Gallery name replaces hyphens with underscores; resource groups use the prefix."
  }
}
