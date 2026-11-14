# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

mock_provider "azapi" {}

variables {
  location            = "eastus2"
  resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-pp"
  delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-net/providers/Microsoft.Network/virtualNetworks/vnet-avd/subnets/snet-powerplatform"
}

run "commercial_deploys_network_injection" {
  command = plan

  assert {
    condition     = length(azapi_resource.vnet_policy) == 1
    error_message = "Expected enterprise policy in commercial cloud."
  }

  assert {
    condition     = output.enterprise_policy_status == "deployed"
    error_message = "Expected deployed status in commercial cloud."
  }

  assert {
    condition     = azapi_resource.vnet_policy[0].body.properties.networkInjection.virtualNetworks[0].subnet.name == "snet-powerplatform"
    error_message = "Expected subnet name extracted from delegated_subnet_id."
  }
}

run "usgov_skips_network_injection" {
  command = plan

  variables {
    cloud = "usgov"
  }

  assert {
    condition     = length(azapi_resource.vnet_policy) == 0
    error_message = "Power Platform VNet injection is unsupported in usgov and must be skipped."
  }

  assert {
    condition     = output.enterprise_policy_status == "skipped: unsupported-in-usgov"
    error_message = "Expected skipped status in usgov."
  }
}
