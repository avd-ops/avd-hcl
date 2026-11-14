# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

terraform {
  required_version = ">= 1.11"
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
  }
}
