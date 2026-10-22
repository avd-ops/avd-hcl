# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), modules/deploy-pipeline/tests; see CREDITS.md and NOTICE.
# Offline plan tests with mocked providers: terraform init -backend=false && terraform test

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "00000000-0000-0000-0000-000000000011"
    }
  }
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
  name            = "avd-sbx"
  location        = "centralus"
  tenant_id       = "00000000-0000-0000-0000-000000000000"
  subscription_id = "00000000-0000-0000-0000-000000000000"
  github = {
    owner      = "contoso"
    repository = "avd-kit"
    reviewers  = ["contoso-admin"]
  }
}

run "gate_and_identities" {
  command = plan

  assert {
    condition     = azurerm_federated_identity_credential.this["plan"].subject == "repo:contoso/avd-kit:environment:sandbox-plan"
    error_message = "The plan identity must trust only the plan environment."
  }
  assert {
    condition     = azurerm_federated_identity_credential.this["apply"].subject == "repo:contoso/avd-kit:environment:sandbox-apply"
    error_message = "The apply identity must trust only the gated apply environment."
  }
  assert {
    condition     = length(github_repository_environment.apply.reviewers) == 1 && !github_repository_environment.apply.can_admins_bypass
    error_message = "Apply must need a reviewer, with no admin bypass."
  }
  assert {
    condition     = length(github_repository_environment.plan.reviewers) == 0
    error_message = "Plan runs shouldn't wait for approval."
  }
  assert {
    condition     = alltrue([for p in github_repository_environment_deployment_policy.this : p.branch_pattern == "main"])
    error_message = "Only main may use either environment."
  }
  assert {
    condition     = azurerm_role_assignment.plan.role_definition_name == "Reader"
    error_message = "The plan identity must stay read-only on the subscription."
  }
  assert {
    condition     = join(",", sort(keys(azuread_app_role_assignment.graph))) == "apply/Application.Read.All,plan/Application.Read.All,plan/Group.Read.All"
    error_message = "Both identities get read-only Graph roles only."
  }
  assert {
    condition     = !azurerm_storage_account.state.shared_access_key_enabled && azurerm_storage_account.state.blob_properties[0].versioning_enabled
    error_message = "State storage must not allow key access and must keep versions."
  }
  assert {
    condition     = keys(azurerm_storage_container.this) == ["answers", "plans", "tfstate"]
    error_message = "Expected the answers, plans and tfstate containers."
  }
  assert {
    condition     = length([for k in keys(github_actions_environment_secret.this) : k if endswith(k, "/AZURE_CLIENT_ID")]) == 2
    error_message = "Each environment gets its own identity's client ID."
  }
}

run "plan_token_role_is_one_action" {
  command = plan

  assert {
    condition     = join(",", azurerm_role_definition.registration_token[0].permissions[0].actions) == "Microsoft.DesktopVirtualization/hostpools/retrieveRegistrationToken/action" && length(coalesce(azurerm_role_definition.registration_token[0].permissions[0].data_actions, [])) == 0
    error_message = "The plan identity's custom role holds only the registration token action."
  }
}

run "plan_token_role_can_be_off" {
  command = plan

  variables {
    plan_reads_registration_token = false
  }

  assert {
    condition     = length(azurerm_role_assignment.plan_registration_token) == 0
    error_message = "Off means no token role for the plan identity."
  }
}

run "longest_name_fits_storage" {
  command = plan

  variables {
    name = "abcdefghijklm"
  }

  assert {
    condition     = length(azurerm_storage_account.state.name) <= 24
    error_message = "Storage account names are at most 24 characters."
  }
}

run "needs_a_reviewer" {
  command = plan

  variables {
    github = {
      owner      = "contoso"
      repository = "avd-kit"
      reviewers  = []
    }
  }

  expect_failures = [var.github]
}

run "private_repository_has_no_gate" {
  command = plan

  override_data {
    target = data.github_repository.this
    values = {
      visibility = "private"
    }
  }

  expect_failures = [github_repository_environment.apply]
}

run "enterprise_private_repository_is_gated" {
  command = plan

  override_data {
    target = data.github_repository.this
    values = {
      visibility = "private"
    }
  }

  variables {
    github = {
      owner      = "contoso"
      repository = "avd-kit"
      reviewers  = ["contoso-admin"]
      enterprise = true
    }
  }

  assert {
    condition     = length(github_repository_environment.apply.reviewers) == 1
    error_message = "On Enterprise a private repository keeps the gate."
  }
}

run "role_admin_is_constrained" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.apply["Role Based Access Control Administrator"].condition_version == "2.0" && strcontains(azurerm_role_assignment.apply["Role Based Access Control Administrator"].condition, "roleAssignments/write")
    error_message = "The apply identity's RBAC administrator role must carry the constrained-delegation condition."
  }
  assert {
    condition     = azurerm_role_assignment.apply["Contributor"].condition == null
    error_message = "Only the role-assignment administrator role needs a condition."
  }
}

run "assignable_roles_never_include_owner" {
  command = plan

  variables {
    apply_assignable_roles = ["Desktop Virtualization User", "Owner"]
  }

  expect_failures = [var.apply_assignable_roles]
}

run "plan_identity_cannot_write_state" {
  command = plan

  assert {
    condition     = !contains(keys(azurerm_role_assignment.state_data), "plan") && azurerm_role_assignment.plan_state_read.role_definition_name == "Storage Blob Data Reader"
    error_message = "The plan identity only reads state and answers."
  }
}

run "apply_roles_never_include_owner" {
  command = plan

  variables {
    apply_roles = ["Owner"]
  }

  expect_failures = [var.apply_roles]
}

run "apply_graph_roles_stay_read_only" {
  command = plan

  variables {
    apply_graph_roles = ["Application.Read.All", "Application.ReadWrite.All"]
  }

  expect_failures = [var.apply_graph_roles]
}
