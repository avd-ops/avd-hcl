# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), packer/avd-win11/plugins.pkr.hcl; see CREDITS.md and NOTICE.

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2.6"
    }
  }
}
