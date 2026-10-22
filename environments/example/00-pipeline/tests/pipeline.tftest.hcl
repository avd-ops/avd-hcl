# The root passes null access fields through, so the module's defaults apply.

mock_provider "azurerm" {
  mock_data "azurerm_role_definition" {
    defaults = {
      role_definition_id = "00000000-0000-0000-0000-000000000099"
    }
  }
}

mock_provider "azuread" {
  mock_data "azuread_service_principal" {
    defaults = {
      object_id = "00000000-0000-0000-0000-000000000022"
      app_role_ids = {
        "Application.Read.All" = "00000000-0000-0000-0000-000000000031"
        "Group.Read.All"       = "00000000-0000-0000-0000-000000000032"
      }
    }
  }
}

mock_provider "github" {
  mock_data "github_user" {
    defaults = {
      id = "1000"
    }
  }
  mock_data "github_repository" {
    defaults = {
      visibility = "public"
    }
  }
}

variables {
  tenant_id       = "00000000-0000-0000-0000-000000000000"
  subscription_id = "00000000-0000-0000-0000-000000000000"
  name            = "avd-sbx"
  github = {
    owner      = "contoso"
    repository = "avd-kit"
    reviewers  = ["contoso-admin"]
  }
}

run "defaults_flow_through" {
  command = plan

  assert {
    condition     = output.github_environments.apply == "sandbox-apply"
    error_message = "The apply environment is <environment>-apply."
  }
}
