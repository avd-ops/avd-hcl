# Per-host-pool estate stage: deploys an independent host pool, application group, scaling
# plan, and session hosts into an existing platform (workspace, VNet, Key Vault, Log Analytics,
# FSLogix share). Allows each pool to be planned, scaled, and rotated without touching shared infra.

locals {
  tags = merge(var.tags, {
    environment = var.environment
    workload    = "avd"
    managed-by  = "terraform"
  })
}

module "control_plane" {
  source                     = "../../../modules/control-plane"
  location                   = var.location
  resource_group_name        = var.control_plane_resource_group_name
  tags                       = local.tags
  identity_model             = var.identity_model
  host_pool_name             = "vdpool-${var.prefix}"
  host_pool_type             = var.host_pool_type
  personal_assignment_type   = var.personal_assignment_type
  app_group_name             = "vdag-${var.prefix}-${lower(var.app_group_type)}"
  app_group_type             = var.app_group_type
  remote_apps                = var.remote_apps
  existing_workspace_id      = var.existing_workspace_id
  scaling_plan_name          = "vdscaling-${var.prefix}"
  scaling_plan_enabled       = var.host_placement == "azure"
  max_sessions_per_host      = var.max_sessions_per_host
  time_zone                  = var.time_zone
  user_group_object_ids      = var.user_group_object_ids
  log_analytics_workspace_id = var.log_analytics_workspace_id
  enable_private_link        = var.enable_private_link
  private_endpoint_subnet_id = var.private_endpoint_subnet_id
  private_dns_zone_id        = var.private_dns_zone_id
}

module "run_secrets" {
  source                  = "../../../modules/run-secrets"
  host_pool_id            = module.control_plane.registration_host_pool_id
  read_registration_token = var.host_count > 0

  providers = {
    azapi.secrets = azapi.secrets
  }
}

module "session_hosts" {
  count                           = var.host_placement == "azure" ? 1 : 0
  source                          = "../../../modules/session-hosts"
  location                        = var.location
  resource_group_name             = var.session_hosts_resource_group_name
  resource_group_id               = var.session_hosts_resource_group_id
  tags                            = local.tags
  identity_model                  = var.identity_model
  host_count                      = var.host_count
  name_prefix                     = var.vm_prefix
  host_generation                 = var.host_generation
  auto_shutdown_time              = var.auto_shutdown_time
  time_zone                       = var.time_zone
  vm_size                         = var.vm_size
  availability_zones              = var.availability_zones
  marketplace_image               = var.image_id == null ? var.marketplace_image : null
  image_id                        = var.image_id
  encryption_at_host              = var.encryption_at_host
  subnet_id                       = var.subnet_id
  enroll_in_intune                = var.enroll_in_intune
  domain_name                     = var.domain_name
  domain_ou_path                  = var.domain_ou_path
  domain_join_username            = var.domain_join_username
  domain_join_password_secret_url = var.domain_join_password_secret_url
  domain_join_key_vault_id        = var.domain_join_key_vault_id
  local_admin_username            = var.local_admin_username
  local_admin_password            = module.run_secrets.local_admin_password
  key_vault_id                    = var.key_vault_id
  registration_token              = module.run_secrets.registration_token
  data_collection_rule_id         = var.data_collection_rule_id
  profile_share_unc               = var.profile_share_unc
  fslogix_profile_size_mib        = var.fslogix_profile_size_mib
  user_group_object_ids           = var.user_group_object_ids
  admin_group_object_ids          = var.admin_group_object_ids

  depends_on = [terraform_data.preflight]
}

module "azure_local_session_hosts" {
  count                    = var.host_placement == "azure-local" ? 1 : 0
  source                   = "../../../modules/azure-local-session-hosts"
  location                 = var.location
  resource_group_id        = var.session_hosts_resource_group_id
  tags                     = local.tags
  host_count               = var.host_count
  name_prefix              = var.vm_prefix
  custom_location_id       = var.custom_location_id
  logical_network_id       = var.azure_local_logical_network_id
  image_id                 = var.azure_local_image_id
  processors               = var.azure_local_processors
  memory_mb                = var.azure_local_memory_mb
  enroll_in_intune         = var.enroll_in_intune
  local_admin_username     = var.local_admin_username
  local_admin_password     = module.run_secrets.local_admin_password
  registration_token       = module.run_secrets.registration_token
  local_smb_profile_path   = var.local_smb_profile_path
  fslogix_profile_size_mib = var.fslogix_profile_size_mib
  host_pool_resource_id    = module.control_plane.host_pool_id

  depends_on = [terraform_data.preflight]
}

resource "terraform_data" "preflight" {
  lifecycle {
    precondition {
      condition     = var.host_placement != "azure" || (var.subnet_id != "" && var.profile_share_unc != "")
      error_message = "subnet_id and profile_share_unc are required when host_placement is azure."
    }
    precondition {
      condition     = var.host_placement != "azure-local" || var.identity_model == "entra_only"
      error_message = "Azure Local v1 supports native Entra ID join (entra_only) only (Decision 0023)."
    }
    precondition {
      condition     = var.host_placement != "azure-local" || (var.custom_location_id != "" && var.azure_local_logical_network_id != "" && var.azure_local_image_id != "")
      error_message = "custom_location_id, azure_local_logical_network_id, and azure_local_image_id are required when host_placement is azure-local."
    }
    precondition {
      condition     = var.host_placement != "azure-local" || var.local_smb_profile_path == "" || can(regex("^\\\\\\\\[^\\\\]+\\\\[^\\\\]+", var.local_smb_profile_path))
      error_message = "local_smb_profile_path must be a UNC share path such as \\\\server\\share."
    }
  }
}
