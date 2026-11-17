mock_provider "azurerm" {
  mock_resource "azurerm_virtual_desktop_host_pool" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/vdpool-eng"
    }
  }
  mock_resource "azurerm_virtual_desktop_application_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/applicationGroups/vdag-eng-desktop"
    }
  }
  mock_resource "azurerm_virtual_desktop_scaling_plan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/scalingPlans/vdscaling-eng"
    }
  }
}

mock_provider "azapi" {}
mock_provider "time" {}

provider "azapi" {
  alias           = "secrets"
  subscription_id = "00000000-0000-0000-0000-000000000000"
  tenant_id       = "00000000-0000-0000-0000-000000000001"
  client_id       = "00000000-0000-0000-0000-000000000007"
  client_secret   = "placeholder-never-used"
  use_cli         = false
  use_msi         = false
  use_oidc        = false
}

variables {
  tenant_id                         = "00000000-0000-0000-0000-000000000001"
  subscription_id                   = "00000000-0000-0000-0000-000000000000"
  location                          = "northcentralus"
  prefix                            = "eng"
  control_plane_resource_group_name = "rg-avd"
  session_hosts_resource_group_name = "rg-hosts"
  session_hosts_resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hosts"
  existing_workspace_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/workspaces/vdws-shared"
  subnet_id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-avd/subnets/snet-hosts"
  key_vault_id                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-storage/providers/Microsoft.KeyVault/vaults/kv-avd"
  log_analytics_workspace_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.OperationalInsights/workspaces/log-avd"
  data_collection_rule_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.Insights/dataCollectionRules/microsoft-avdi-avd"
  profile_share_unc                 = "\\\\stprofiles.file.core.windows.net\\profiles"
  user_group_object_ids             = ["00000000-0000-0000-0000-000000000004"]
  host_count                        = 0
}

run "attaches_pool_to_existing_workspace" {
  command = plan

  assert {
    condition     = output.host_pool_name == "vdpool-eng" && output.session_host_names == []
    error_message = "Independent host pool stage plans cleanly against an existing platform."
  }
}

run "remote_app_pool" {
  command = plan

  variables {
    app_group_type = "RemoteApp"
    remote_apps = {
      calc = {
        friendly_name = "Calculator"
        path          = "C:\\Windows\\System32\\calc.exe"
      }
    }
  }

  assert {
    condition     = output.host_pool_name == "vdpool-eng"
    error_message = "RemoteApp host pool plans cleanly."
  }
}

run "azure_local_host_pool" {
  command = plan

  variables {
    host_placement                 = "azure-local"
    custom_location_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hci/providers/Microsoft.ExtendedLocation/customLocations/cl-test"
    azure_local_logical_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hci/providers/Microsoft.AzureStackHCI/logicalNetworks/lnet-avd"
    azure_local_image_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hci/providers/Microsoft.AzureStackHCI/galleryImages/win11-avd"
    local_smb_profile_path         = "\\\\files01.contoso.com\\profiles"
    subnet_id                      = ""
    profile_share_unc              = ""
  }

  assert {
    condition     = output.azure_local != null && output.azure_local.host_placement == "azure-local" && output.azure_local.custom_location_id == var.custom_location_id && output.azure_local.logical_network_id == var.azure_local_logical_network_id
    error_message = "Azure Local host pool emits the azure_local output block."
  }

  assert {
    condition     = length(output.session_host_names) == 0
    error_message = "Zero host_count produces empty session_host_names."
  }
}

run "azure_local_rejects_adds" {
  command = plan

  variables {
    host_placement                 = "azure-local"
    identity_model                 = "ad_ds"
    custom_location_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hci/providers/Microsoft.ExtendedLocation/customLocations/cl-test"
    azure_local_logical_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hci/providers/Microsoft.AzureStackHCI/logicalNetworks/lnet-avd"
    azure_local_image_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hci/providers/Microsoft.AzureStackHCI/galleryImages/win11-avd"
    subnet_id                      = ""
    profile_share_unc              = ""
  }

  expect_failures = [terraform_data.preflight]
}
