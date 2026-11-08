---
title: "Platform stage: modules and gotchas"
summary: "What the platform stage builds, how each module maps to the landing zone's design, and what writing it in Terraform on azurerm 5 taught"
topic: platform
status: built-offline
last_reviewed: 2026-10-21
---

# Platform stage: modules and gotchas

`environments/example/01-platform` builds a pooled or personal Entra-joined host pool in one apply,
from the modules in `modules/`, and `environments/example/02-images` builds the Azure Compute
Gallery that `packer/avd-win11` publishes golden images into. Everything is tested offline with
`terraform test` and mocked providers; it has not run against Azure yet (that needs a written
estimate and the owner's exact go).

| Module | What it builds | Comes from |
|---|---|---|
| `foundation` | Resource groups by role (network, control plane, session hosts, storage, monitoring) | nerdio-hcl `modules/foundation` |
| `network` | Spoke VNet, session host and private endpoint subnets, NSGs, privatelink zones, optional hub peering, NAT gateway | nerdio-hcl `modules/network` |
| `fslogix-storage` | Premium Azure Files with Entra Kerberos, private endpoint, SMB roles, logs | nerdio-hcl `modules/fslogix-storage` |
| `key-vault` | RBAC vault with purge protection and a private endpoint, holding the break-glass credential | avd-landing-zone `keyVault.bicep` |
| `monitoring` | Log Analytics (Entra auth only), AVD Insights data collection rule, optional alert action group and monthly subscription budget | avd-landing-zone `monitoring.bicep` and `budget.bicep` |
| `control-plane` | Pooled or Personal host pool, registration token, desktop app group, workspace, user assignment, pooled scaling plan, diagnostics | avd-landing-zone `controlPlane.bicep` |
| `session-hosts` | Trusted Launch VMs with blue/green `host_generation` naming, a break-glass secret per host, Entra join (optional Intune), AMA, guest configuration, the two run commands, optional daily auto-shutdown, sign-in roles | avd-landing-zone `sessionHosts.bicep`, `autoShutdown.bicep` and `scripts/sessionhost/` |
| `image-gallery` | Azure Compute Gallery and Trusted Launch image definition for `02-images` and `packer/avd-win11` | nerdio-hcl `modules/image-gallery` and avd-landing-zone `imagePipeline.bicep` |
| `run-secrets` | The run's ephemeral values: a new break-glass password and the host pool's registration token | New |

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
- **The admin password is generated and kept in Key Vault** (lesson 0002), one secret per host,
  written once, because Azure applies it only at creation.
- **Extensions and run commands ignore later changes** (lesson 0026): rewriting them fails on a
  host autoscale has deallocated. A new token, tag or FSLogix setting reaches hosts by rebuilding
  them via `host_generation` (`""`, `"a"`, or `"b"`).
- **Key Vault and Log Analytics soft delete** (lessons 0022 and 0023): the provider recovers a
  soft-deleted vault and deletes the workspace permanently on destroy.
- **WDOT silent failure when its event log is missing** (lesson 0031): `packer/avd-win11/scripts/03-wdot.ps1`
  creates the `WDOT` classic event log before running `Windows_VDOT.ps1` and checks for the
  `HKLM:\SOFTWARE\WDOT` marker key afterward so a silent skip fails the image build.
- **Personal host pools skip the pooled scaling plan**: `control-plane` sets `Persistent` load
  balancing, `Automatic` or `Direct` personal assignment, `maximum_sessions_allowed = 1`, and
  `start_vm_on_connect = true`, while skipping `azurerm_virtual_desktop_scaling_plan` unless the
  pool is `Pooled`.
- **Blue/green host naming stays within the 15-character NetBIOS limit**: `session-hosts` appends
  `host_generation` (`"a"` or `"b"`) after `substr(name_prefix, 0, 10)` so `<prefix><gen>-NNN`
  never exceeds 15 characters.

## Gotchas found while writing it

- **Power On Off Contributor belongs at subscription scope.** Microsoft's autoscale page says a
  lower scope, such as a resource group, "prevents autoscale from working properly"
  ([Learn](https://learn.microsoft.com/azure/virtual-desktop/autoscale-create-assign-scaling-plan#assign-permissions-to-the-azure-virtual-desktop-service-principal)).
  The root grants it there; the landing zone grants it on its two resource groups.
- **No secret in state** (guardrail 5). azurerm 5.10 has write-only attributes for a few
  resources, but not for a VM's `admin_password`, a run command's protected parameters or the
  host pool registration token, which `azurerm_virtual_desktop_host_pool_registration_info` keeps
  in state. So:
  - the password is an ephemeral `random_password`;
  - the token's expiry is set on the host pool with `azapi_update_resource`, and the token is
    read with the ephemeral `azapi_resource_action` `retrieveRegistrationToken`;
  - the VM, the per-host password secret and the registration run command are `azapi_resource`s
    whose `sensitive_body` is write-only, with a fixed `sensitive_body_version` so each is written
    once.
- **A Key Vault with public access off can't be written through its data plane** from a runner
  outside the VNet. `azurerm_key_vault_secret` uses the data plane, so secrets go through ARM
  (`Microsoft.KeyVault/vaults/secrets`) with azapi.
- **Run commands through ARM fail the apply when their script fails**, with `asyncExecution =
  false` and `treatFailureAsDeploymentFailure = true`, the same as the landing zone's Bicep.
  azurerm's run command resource has no such setting.
- **A host keeps the zone it was created in.** Zones are handed out round robin, so editing
  `availability_zones` would move existing hosts and rebuild them; the VM ignores later zone
  changes, so the edit applies to new hosts only.
- **Session hosts need exactly one way out.** The subnets have no default outbound access, and
  peering alone doesn't send internet traffic through a hub, so without the NAT gateway the
  network module routes 0.0.0.0/0 to `egress_firewall_ip`. A plan with neither fails.
- **The NSG's outbound allow rules restrict nothing** while the default AllowInternetOutBound rule
  applies. They name the flows; locking egress down is the hub firewall's job or later hardening.
- **Power On Off Contributor is one assignment per subscription.** A second environment in the
  same subscription sets `grant_avd_power_role = false`, or the apply fails on the existing
  assignment and a destroy would remove it from every host pool.
- **Encryption at host needs a subscription feature.** The root reads
  `Microsoft.Compute/EncryptionAtHost` at plan time and stops before creating anything when it
  isn't registered, with the commands to fix it.
- **Mock providers can't hold ephemeral resources** ("No ephemeral resource types in mock
  providers"), even with `override_module`. The ephemeral reads use their own provider alias
  (`azapi.secrets`), which the root test configures as a real provider with placeholder settings
  and never calls, because the test plans zero hosts and skips the read. The random provider runs
  unmocked; it works offline.
- **Azure rejects Key Vault names with two hyphens in a row**, so the prefix allows single hyphens
  only.
- **`count` can't depend on an ID from the same apply.** `count = var.workspace_id == null ? 0 : 1`
  fails at plan when the workspace is created in the same run; the root test caught it. The
  modules take the workspace ID as required instead.
- **Mock providers return unknown computed values at plan**, so a test asserts on inputs (or on
  `mock_resource` defaults for IDs that other resources validate), not on computed attributes.
- **azurerm validates resource ID shapes at plan**, so test inputs need full, well-formed
  placeholder IDs, not short strings.
