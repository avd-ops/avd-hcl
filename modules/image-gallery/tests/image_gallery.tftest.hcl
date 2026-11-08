mock_provider "azurerm" {
  mock_resource "azurerm_shared_image_gallery" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test-images/providers/Microsoft.Compute/galleries/gal_test_avd"
    }
  }
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test-images-build"
    }
  }
}

variables {
  gallery_name              = "gal_test_avd"
  location                  = "eastus2"
  resource_group_name       = "rg-test-images"
  build_resource_group_name = "rg-test-images-build"
}

run "trusted_launch_gallery" {
  command = plan

  assert {
    condition     = azurerm_shared_image.this["win11-24h2-avd-m365"].hyper_v_generation == "V2" && azurerm_shared_image.this["win11-24h2-avd-m365"].trusted_launch_supported
    error_message = "Image definitions must be Gen2 and Trusted Launch."
  }

  assert {
    condition     = length(azurerm_role_assignment.packer_gallery) == 0 && length(azurerm_role_assignment.packer_build) == 0
    error_message = "No Packer role assignments when packer_principal_id is null."
  }
}

run "packer_identity_roles" {
  command = plan

  variables {
    packer_principal_id = "00000000-0000-0000-0000-000000000009"
  }

  assert {
    condition     = azurerm_role_assignment.packer_gallery[0].role_definition_name == "Contributor" && azurerm_role_assignment.packer_build[0].role_definition_name == "Contributor"
    error_message = "Packer identity gets Contributor on the gallery and build resource group only."
  }
}

run "bad_gallery_name_is_rejected" {
  command = plan

  variables {
    gallery_name = "gal-with-hyphens"
  }

  expect_failures = [var.gallery_name]
}
