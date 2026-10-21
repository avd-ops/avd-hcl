# The two secrets a run needs, opened ephemerally so neither is ever written to state or a plan
# file (guardrail 5): the break-glass password for hosts created in this run, and the host pool's
# current registration token. Both are only passed to write-only attributes.

ephemeral "random_password" "local_admin" {
  length           = 24
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#%*()-_=+[]{}:?"
}

# modules/control-plane sets the token's expiry; pass its registration_host_pool_id so that
# happens first. Skipped when the run has no hosts to register.
ephemeral "azapi_resource_action" "registration_token" {
  provider               = azapi.secrets
  count                  = var.read_registration_token ? 1 : 0
  type                   = "Microsoft.DesktopVirtualization/hostPools@2024-04-03"
  resource_id            = var.host_pool_id
  action                 = "retrieveRegistrationToken"
  method                 = "POST"
  response_export_values = ["token"]
}
