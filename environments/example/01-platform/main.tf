# The platform stage: everything one pooled, Entra-joined AVD host pool needs, in one apply.
# Each module is in ../../../modules; this root only names things and wires outputs to inputs.

data "azurerm_subscription" "current" {}

# The Azure Virtual Desktop service principal (Microsoft's well-known application ID, the same
# in every tenant). Autoscale and Start VM on Connect act as it.
data "azuread_service_principal" "avd" {
  count     = var.avd_service_principal_object_id == null ? 1 : 0
  client_id = "9cdead84-a844-4324-93f2-b2e6bb768d07"
}

locals {
  # A short, stable suffix keeps globally unique names (storage, Key Vault) unique per
  # subscription, region and prefix, and the same on every run.
  suffix  = substr(sha1("${var.subscription_id}/${var.location}/${var.prefix}"), 0, 6)
  compact = replace(var.prefix, "-", "")

  names = {
    resource_groups = {
      network       = "rg-${var.prefix}-network"
      control_plane = "rg-${var.prefix}-avd"
      session_hosts = "rg-${var.prefix}-hosts"
      storage       = "rg-${var.prefix}-storage"
      monitoring    = "rg-${var.prefix}-monitoring"
    }
    log_analytics   = "log-${var.prefix}-avd"
    key_vault       = "kv-${var.prefix}-${local.suffix}"
    storage_account = "st${local.compact}${local.suffix}"
    host_pool       = "vdpool-${var.prefix}"
    app_group       = "vdag-${var.prefix}-desktop"
    workspace       = "vdws-${var.prefix}"
    scaling_plan    = "vdscaling-${var.prefix}"
  }

  tags = merge(var.tags, {
    environment = var.environment
    workload    = "avd"
    managed-by  = "terraform"
  })

  avd_service_principal_object_id = coalesce(var.avd_service_principal_object_id, try(data.azuread_service_principal.avd[0].object_id, null))
}

module "foundation" {
  source          = "../../../modules/foundation"
  location        = var.location
  tags            = local.tags
  resource_groups = local.names.resource_groups
}

module "network" {
  source              = "../../../modules/network"
  prefix              = var.prefix
  location            = var.location
  resource_group_name = module.foundation.resource_group_names["network"]
  tags                = local.tags
  address_space       = var.address_space
  subnets             = var.subnets
  dns_servers         = var.dns_servers
  availability_zones  = var.availability_zones
  hub_vnet_id         = var.hub_vnet_id
  create_nat_gateway  = var.create_nat_gateway
  egress_firewall_ip  = var.egress_firewall_ip
}

module "monitoring" {
  source                = "../../../modules/monitoring"
  prefix                = var.prefix
  name                  = local.names.log_analytics
  location              = var.location
  resource_group_name   = module.foundation.resource_group_names["monitoring"]
  tags                  = local.tags
  retention_in_days     = var.log_retention_days
  subscription_id       = data.azurerm_subscription.current.id
  alert_email_addresses = var.alert_email_addresses
  monthly_budget_amount = var.monthly_budget_amount
  budget_start_date     = var.budget_start_date
}

module "key_vault" {
  source                     = "../../../modules/key-vault"
  name                       = local.names.key_vault
  location                   = var.location
  resource_group_name        = module.foundation.resource_group_names["storage"]
  tags                       = local.tags
  private_endpoint_subnet_id = module.network.subnet_ids["private_endpoints"]
  private_dns_zone_id        = module.network.private_dns_zone_ids["vault"]
  local_admin_username       = var.local_admin_username
  admin_group_object_ids     = var.admin_group_object_ids
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
}

module "fslogix" {
  source                     = "../../../modules/fslogix-storage"
  name                       = local.names.storage_account
  location                   = var.location
  resource_group_name        = module.foundation.resource_group_names["storage"]
  tags                       = local.tags
  share_quota_gb             = var.fslogix_share_quota_gb
  replication_type           = length(var.availability_zones) == 0 ? "LRS" : "ZRS"
  private_endpoint_subnet_id = module.network.subnet_ids["private_endpoints"]
  private_dns_zone_id        = module.network.private_dns_zone_ids["file"]
  user_group_object_ids      = var.user_group_object_ids
  admin_group_object_ids     = var.admin_group_object_ids
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
}

# Microsoft documents this role at subscription scope: autoscale doesn't work properly when it
# is granted lower, such as on a resource group. One assignment serves every host pool in the
# subscription, so only one root (or the landing zone) owns it: set grant_avd_power_role = false
# in every other environment of the same subscription, or destroying one would remove it from all.
resource "azurerm_role_assignment" "avd_power_on_off" {
  count                = var.grant_avd_power_role ? 1 : 0
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Desktop Virtualization Power On Off Contributor"
  principal_id         = local.avd_service_principal_object_id
  principal_type       = "ServicePrincipal"
}

module "control_plane" {
  source                     = "../../../modules/control-plane"
  location                   = var.location
  resource_group_name        = module.foundation.resource_group_names["control_plane"]
  tags                       = local.tags
  host_pool_name             = local.names.host_pool
  host_pool_friendly_name    = var.host_pool_friendly_name
  host_pool_type             = var.host_pool_type
  personal_assignment_type   = var.personal_assignment_type
  app_group_name             = local.names.app_group
  workspace_name             = local.names.workspace
  workspace_friendly_name    = var.workspace_friendly_name
  scaling_plan_name          = local.names.scaling_plan
  max_sessions_per_host      = var.max_sessions_per_host
  time_zone                  = var.time_zone
  user_group_object_ids      = var.user_group_object_ids
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  # The scaling plan is checked against the service principal's role when it is created.
  depends_on = [azurerm_role_assignment.avd_power_on_off]
}

module "session_hosts" {
  source                   = "../../../modules/session-hosts"
  location                 = var.location
  resource_group_name      = module.foundation.resource_group_names["session_hosts"]
  resource_group_id        = module.foundation.resource_group_ids["session_hosts"]
  tags                     = local.tags
  host_count               = var.host_count
  name_prefix              = var.vm_prefix
  host_generation          = var.host_generation
  auto_shutdown_time       = var.auto_shutdown_time
  time_zone                = var.time_zone
  vm_size                  = var.vm_size
  availability_zones       = var.availability_zones
  marketplace_image        = var.image_id == null ? var.marketplace_image : null
  image_id                 = var.image_id
  encryption_at_host       = var.encryption_at_host
  subnet_id                = module.network.subnet_ids["session_hosts"]
  enroll_in_intune         = var.enroll_in_intune
  local_admin_username     = var.local_admin_username
  local_admin_password     = module.run_secrets.local_admin_password
  key_vault_id             = module.key_vault.key_vault_id
  registration_token       = module.run_secrets.registration_token
  data_collection_rule_id  = module.monitoring.data_collection_rule_id
  profile_share_unc        = module.fslogix.profile_share_unc
  fslogix_profile_size_mib = var.fslogix_profile_size_mib
  user_group_object_ids    = var.user_group_object_ids
  admin_group_object_ids   = var.admin_group_object_ids

  # The hosts mount the profile share over its private endpoint as they register.
  depends_on = [module.fslogix, terraform_data.preflight]
}

# Secrets for this run, never stored: see modules/run-secrets.
module "run_secrets" {
  source                  = "../../../modules/run-secrets"
  host_pool_id            = module.control_plane.registration_host_pool_id
  read_registration_token = var.host_count > 0

  providers = {
    azapi.secrets = azapi.secrets
  }
}

# Encryption at host needs a subscription feature. Read it at plan time, so a subscription without
# it stops the plan before anything is created, instead of failing at the first VM.
data "azapi_resource" "encryption_at_host_feature" {
  count                  = var.encryption_at_host ? 1 : 0
  type                   = "Microsoft.Features/providers/features@2021-07-01"
  resource_id            = "${data.azurerm_subscription.current.id}/providers/Microsoft.Features/providers/Microsoft.Compute/features/EncryptionAtHost"
  response_export_values = ["properties.state"]
}

resource "terraform_data" "preflight" {
  lifecycle {
    precondition {
      condition     = !var.encryption_at_host || try(data.azapi_resource.encryption_at_host_feature[0].output.properties.state, "") == "Registered"
      error_message = "encryption_at_host needs the Microsoft.Compute/EncryptionAtHost feature: run `az feature register --namespace Microsoft.Compute --name EncryptionAtHost`, wait until it shows Registered, then `az provider register -n Microsoft.Compute`. Or set encryption_at_host = false."
    }
  }
}
