# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), packer/avd-win11/example.pkrvars.hcl; see CREDITS.md and NOTICE.

subscription_id      = "00000000-0000-0000-0000-000000000000"
tenant_id            = "00000000-0000-0000-0000-000000000001"
location             = "eastus2"
build_resource_group = "rg-avd-sandbox-images-build"

gallery = {
  resource_group   = "rg-avd-sandbox-images"
  name             = "gal_avd_sandbox_avd"
  image_definition = "win11-24h2-avd-m365"
  replica_regions  = ["eastus2"]
}

# Optional: Windows Desktop Optimization Tool profile and per-setting changes (see README.md).
# wdot_profile   = "avd-multisession"
# wdot_overrides = { Services = { SysMain = "Apply" } }
