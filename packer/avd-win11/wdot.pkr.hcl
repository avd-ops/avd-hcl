# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), packer/avd-win11/wdot.pkr.hcl; see CREDITS.md and NOTICE.
# Changes: profile_name is avd-hcl, and DiskCleanup is omitted so build logs and event logs stay intact for verification.
#
# Windows Desktop Optimization Tool (WDOT), the successor to VDOT.
# https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool
#
# The policy lives here in HCL; scripts/03-wdot.ps1 only applies it. WDOT ships every setting
# as "Skip", so a profile names the config files whose settings flip to "Apply" and the WDOT
# categories to run. var.wdot_overrides adjusts single settings on top of the profile.
#
# The build host fetches WDOT with git at a pinned commit (content-addressed, so no separate
# checksum) and uploads it, so the build VM never downloads code from GitHub itself.

locals {
  wdot_profiles = {
    # The same selection as Microsoft's own sample profile (Configurations/2009), minus DiskCleanup
    # (which deletes C:\Windows\Temp and .evtx files before verification; avd-landing-zone spec 5.5).
    avd-multisession = {
      optimizations          = ["Autologgers", "DefaultUserSettings", "LocalPolicy", "NetworkOptimizations"]
      advanced_optimizations = ["Edge"]
      apply_all              = ["Autologgers", "DefaultUserSettings", "EdgeSettings", "LanManWorkstation", "PolicyRegSettings"]
    }
    # Low-impact settings only: SMB client tuning and autologgers.
    minimal = {
      optimizations          = ["Autologgers", "NetworkOptimizations"]
      advanced_optimizations = []
      apply_all              = ["Autologgers", "LanManWorkstation"]
    }
    none = {
      optimizations          = []
      advanced_optimizations = []
      apply_all              = []
    }
  }

  # The WDOT category that reads each config file, so an override turns its category on.
  wdot_file_category = {
    AppxPackages        = "AppxPackages"
    Autologgers         = "Autologgers"
    DefaultUserSettings = "DefaultUserSettings"
    LanManWorkstation   = "NetworkOptimizations"
    PolicyRegSettings   = "LocalPolicy"
    ScheduledTasks      = "ScheduledTasks"
    Services            = "Services"
  }

  wdot_profile = local.wdot_profiles[var.wdot_profile]
  wdot_enabled = var.wdot_profile != "none"
  wdot_zip     = "${path.root}/packer_cache/wdot-${var.wdot_source.commit}.zip"

  wdot_settings = {
    enabled      = local.wdot_enabled
    profile_name = "avd-hcl"
    optimizations = distinct(concat(
      local.wdot_profile.optimizations,
      [for f in keys(var.wdot_overrides) : local.wdot_file_category[f] if f != "EdgeSettings"],
    ))
    advanced_optimizations = distinct(concat(
      local.wdot_profile.advanced_optimizations,
      contains(keys(var.wdot_overrides), "EdgeSettings") ? ["Edge"] : [],
    ))
    apply_all = local.wdot_profile.apply_all
    overrides = var.wdot_overrides
  }
}
