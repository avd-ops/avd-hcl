# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

resource "azurerm_resource_group" "hub" {
  name     = "rg-${var.prefix}-${var.environment}"
  location = var.location
  tags     = var.tags
}

module "hub_network" {
  source = "../../../modules/hub-network"

  prefix              = var.prefix
  cloud               = var.cloud
  environment         = var.environment
  profile             = var.profile
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  tags                = var.tags
}
