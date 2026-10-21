---
title: "Platform stage: modules and gotchas"
summary: "What the platform stage builds, how each module maps to the landing zone's design, and what writing it in Terraform on azurerm 5 taught"
topic: platform
status: built-offline
last_reviewed: 2026-10-21
---

# Platform stage: modules and gotchas

`environments/example/01-platform` builds one pooled, Entra-joined host pool in one apply, from the
modules in `modules/`. Everything is tested offline with `terraform test` and mocked providers; it
has not run against Azure yet (that needs a written estimate and the owner's exact go).

| Module | What it builds | Comes from |
|---|---|---|
| `foundation` | Resource groups by role (network, control plane, session hosts, storage, monitoring) | nerdio-hcl `modules/foundation` |
| `network` | Spoke VNet, session host and private endpoint subnets, NSGs, privatelink zones, optional hub peering, NAT gateway | nerdio-hcl `modules/network` |
| `fslogix-storage` | Premium Azure Files with Entra Kerberos, private endpoint, SMB roles, logs | nerdio-hcl `modules/fslogix-storage` |
| `key-vault` | RBAC vault with purge protection and a private endpoint, holding the break-glass credential | avd-landing-zone `keyVault.bicep` |
| `monitoring` | Log Analytics (Entra auth only) and the AVD Insights data collection rule | avd-landing-zone `monitoring.bicep` |
| `control-plane` | Host pool, registration token, desktop app group, workspace, user assignment, scaling plan, diagnostics | avd-landing-zone `controlPlane.bicep` |
| `session-hosts` | Trusted Launch VMs, Entra join (optional Intune), AMA, guest configuration, the two run commands, sign-in roles | avd-landing-zone `sessionHosts.bicep` and `scripts/sessionhost/` |

The parameter schema (`schema/parameters.json`) answers the root's variables; `scripts/schema/check.py`
fails CI when a parameter points at a variable that doesn't exist, or a required variable has no
parameter.

## Lessons carried over as tests

Each is a `terraform test` run, so a change that undoes it fails CI.

- **NAT gateway IP zones follow the region** (landing zone lesson 0001): no zones means a regional
  IP. nerdio-hcl's module always sets zones 1-3, which fails in a region without zones.
- **SMB channel encryption allows AES-128-GCM and AES-256-GCM** (landing zone lesson 0028):
  AES-256-GCM alone denies Entra Kerberos sign-ins from cloud-only users. nerdio-hcl's module sets
  AES-256-GCM only.
- **The admin password is generated and kept in Key Vault** (lesson 0002), and hosts ignore later
  password changes, because Azure applies it only at creation.
- **The registration run command ignores a new token** (lesson 0026): rewriting it on every apply
  fails on a deallocated host.
- **Key Vault and Log Analytics soft delete** (lessons 0022 and 0023): the provider recovers a
  soft-deleted vault and deletes the workspace permanently on destroy.

## Gotchas found while writing it

- **Power On Off Contributor belongs at subscription scope.** Microsoft's autoscale page says a
  lower scope, such as a resource group, "prevents autoscale from working properly"
  ([Learn](https://learn.microsoft.com/azure/virtual-desktop/autoscale-create-assign-scaling-plan#assign-permissions-to-the-azure-virtual-desktop-service-principal)).
  The root grants it there; the landing zone grants it on its two resource groups.
- **A Key Vault with public access off can't be written through its data plane** from a runner
  outside the VNet. `azurerm_key_vault_secret` uses the data plane, so the secrets go through ARM
  with `azapi_resource` (`Microsoft.KeyVault/vaults/secrets`) instead. Its `sensitive_body` is
  write-only, so that resource keeps no password in state. The VM's `admin_password` has no
  write-only form in azurerm 5.10, so the password is still in state: the backend must be private
  and Entra-authenticated.
- **`count` can't depend on an ID from the same apply.** `count = var.workspace_id == null ? 0 : 1`
  fails at plan when the workspace is created in the same run; the root test caught it. The
  modules take the workspace ID as required instead.
- **Mock providers return unknown computed values at plan**, so a test asserts on inputs (or on
  `mock_resource` defaults for IDs that other resources validate), not on computed attributes.
- **azurerm validates resource ID shapes at plan**, so test inputs need full, well-formed
  placeholder IDs, not short strings.
- **Run commands don't fail the apply on their own.** Each run command has a postcondition on the
  instance view's exit code, so a script that fails stops the apply instead of passing silently.
