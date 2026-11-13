# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
# Terraform port of avd-power-platform/bicep/main.bicep.

locals {
  vnet_injection_supported = var.cloud == "commercial"
  subnet_parts             = split("/subnets/", var.delegated_subnet_id)
  vnet_id                  = local.subnet_parts[0]
  subnet_name              = element(local.subnet_parts, length(local.subnet_parts) - 1)
}

resource "azapi_resource" "vnet_policy" {
  count     = local.vnet_injection_supported ? 1 : 0
  type      = "Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview"
  name      = var.enterprise_policy_name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags

  body = {
    kind = "NetworkInjection"
    properties = {
      networkInjection = {
        virtualNetworks = [
          {
            id = local.vnet_id
            subnet = {
              name = local.subnet_name
            }
          }
        ]
      }
    }
  }
}
