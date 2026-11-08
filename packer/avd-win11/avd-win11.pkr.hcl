# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), packer/avd-win11/avd-win11.pkr.hcl; see CREDITS.md and NOTICE.
# Changes: passes DISCONNECTED_HOURS to 01-base.ps1; no Ansible or Evergreen steps.

locals {
  image_version = var.image_version != "" ? var.image_version : formatdate("YYYY.MMDD.hhmm", timestamp())
}

source "azure-arm" "avd" {
  subscription_id    = var.subscription_id
  tenant_id          = var.tenant_id
  use_azure_cli_auth = var.use_azure_cli_auth

  build_resource_group_name = var.build_resource_group
  vm_size                   = var.vm_size

  virtual_network_name                   = try(var.build_subnet.vnet, null)
  virtual_network_subnet_name            = try(var.build_subnet.subnet, null)
  virtual_network_resource_group_name    = try(var.build_subnet.resource_group, null)
  private_virtual_network_with_public_ip = false

  os_type         = "Windows"
  image_publisher = var.source_image.publisher
  image_offer     = var.source_image.offer
  image_sku       = var.source_image.sku
  image_version   = var.source_image.version

  # Match the gallery image definition: Gen2 with Trusted Launch.
  secure_boot_enabled = true
  vtpm_enabled        = true
  security_type       = "TrustedLaunch"

  communicator   = "winrm"
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_timeout  = "15m"
  winrm_username = "packer"

  shared_image_gallery_destination {
    subscription         = var.subscription_id
    resource_group       = var.gallery.resource_group
    gallery_name         = var.gallery.name
    image_name           = var.gallery.image_definition
    image_version        = local.image_version
    replication_regions  = var.gallery.replica_regions
    storage_account_type = "Standard_ZRS"
  }

  azure_tags = merge(var.tags, {
    "built-by"     = "packer"
    "wdot-profile" = var.wdot_profile
    "wdot-commit"  = local.wdot_enabled ? substr(var.wdot_source.commit, 0, 12) : "none"
  })
}

build {
  name    = "avd-win11"
  sources = ["source.azure-arm.avd"]

  provisioner "powershell" {
    script = "${path.root}/scripts/01-base.ps1"
    env = {
      TIMEZONE           = var.timezone
      DISCONNECTED_HOURS = tostring(var.disconnected_session_hours)
      GPU_PRESET         = var.gpu_preset ? "True" : "False"
    }
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    script            = "${path.root}/scripts/02-windows-update.ps1"
    elevated_user     = build.User
    elevated_password = build.Password
    valid_exit_codes  = [0, 3010]
    env = {
      RUN_WINDOWS_UPDATE = var.run_windows_update ? "True" : "False"
    }
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # WDOT: fetched on the build host at a pinned commit, uploaded, then applied with the HCL
  # profile from wdot.pkr.hcl. With wdot_profile = "none" the fetch writes an empty placeholder.
  provisioner "shell-local" {
    environment_vars = [
      "WDOT_ENABLED=${local.wdot_enabled}",
      "WDOT_REPOSITORY=${var.wdot_source.repository}",
      "WDOT_COMMIT=${var.wdot_source.commit}",
      "WDOT_ZIP=${local.wdot_zip}",
    ]
    inline = [
      "set -eu",
      "mkdir -p \"$(dirname \"$WDOT_ZIP\")\"",
      "if [ \"$WDOT_ENABLED\" != true ]; then : > \"$WDOT_ZIP\"; exit 0; fi",
      "if [ -s \"$WDOT_ZIP\" ]; then exit 0; fi",
      "tmp=$(mktemp -d)",
      "git -C \"$tmp\" init -q",
      "git -C \"$tmp\" fetch -q --depth 1 \"$WDOT_REPOSITORY\" \"$WDOT_COMMIT\"",
      "test \"$(git -C \"$tmp\" rev-parse FETCH_HEAD)\" = \"$WDOT_COMMIT\"",
      "git -C \"$tmp\" archive --format=zip --prefix=wdot/ -o \"$WDOT_ZIP.part\" FETCH_HEAD",
      "mv \"$WDOT_ZIP.part\" \"$WDOT_ZIP\"",
      "rm -rf \"$tmp\"",
    ]
  }

  provisioner "file" {
    source      = local.wdot_zip
    destination = "C:/Windows/Temp/wdot.zip"
    generated   = true
  }

  provisioner "file" {
    content     = jsonencode(local.wdot_settings)
    destination = "C:/Windows/Temp/wdot-settings.json"
  }

  provisioner "powershell" {
    script            = "${path.root}/scripts/03-wdot.ps1"
    elevated_user     = build.User
    elevated_password = build.Password
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    script = "${path.root}/scripts/99-sysprep.ps1"
  }
}
