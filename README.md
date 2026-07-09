# AVD Lab Kit

> **Status: in progress — nothing here deploys end-to-end yet.**
> The Bicep modules for networking, storage, and the AVD control plane compile and are ready to deploy individually. The orchestrator that strings them together does not exist. This README describes **what actually works today**, not what the finished tool will do. See [Current state](#current-state) for the exact line.

A fully scripted, repeatable Azure Virtual Desktop lab — "AVD as code." Spin it up, demonstrate the pattern, tear it down cleanly in one command. Bicep modules handle everything that's a clean ARM resource; a thin PowerShell orchestrator wraps them for the things that aren't (Microsoft Graph calls, Microsoft Entra Kerberos enablement, and step-by-step narration you can talk over during a live demo).

This is deliberately the **Easy Mode** build: Entra ID-joined session hosts, no domain controller, no on-prem dependency, one resource group. It's meant to be understood in one sitting and forked without standing up AD DS first. See [Easy Mode / Hard Mode](#easy-mode--hard-mode) for what that leaves out, and why saying so out loud is the point.

## Current state

| Component | Status |
| --- | --- |
| `bicep/modules/network.bicep` — VNet, subnet, NSG, NAT gateway | Compiles; not yet deployed to Azure |
| `bicep/modules/storage.bicep` — Azure Files + Entra Kerberos toggle | Compiles; not yet deployed to Azure |
| `bicep/modules/hostpool.bicep` — pooled host pool + registration token | Compiles; not yet deployed to Azure |
| `bicep/modules/appgroup.bicep` — desktop application group | Compiles; not yet deployed to Azure |
| `bicep/modules/workspace.bicep` — workspace | Compiles; not yet deployed to Azure |
| `bicep/parameters/avdlab.bicepparam` | Placeholders only |
| `scripts/Initialize-AvdLabPrerequisites.ps1` | Runnable |
| `scripts/Set-AvdLabFSLogixAuth.ps1` | Runnable; never yet run against a real tenant |
| `sessionhosts.bicep`, `monitoring.bicep`, `scalingplan.bicep` | Not written |
| `Deploy-AvdLab.ps1`, `Remove-AvdLab.ps1`, `Add-AvdLabAssignments.ps1`, `Test-AvdLabDeployment.ps1`, `New-AvdLabReport.ps1` | Not written |
| CI: Bicep build, Pester, gitleaks history scan | Green |

Everything above is verified against compilers and mocked API responses. **Nothing has been deployed to a real Azure subscription yet.** Treat the modules as reviewed code, not as tested infrastructure.

## Prerequisites

**PowerShell 7+**, and:

```powershell
Install-Module Az.Accounts, Az.Resources, Az.Storage -Scope CurrentUser
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications, `
               Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Users, `
               Microsoft.Graph.Groups -Scope CurrentUser
az bicep install    # or the VS Code Bicep extension
```

`Microsoft.Graph.Applications` and `Microsoft.Graph.Identity.SignIns` are required by `Set-AvdLabFSLogixAuth.ps1`. `Initialize-AvdLabPrerequisites.ps1` deliberately needs neither — it queries the REST endpoints directly, so the one script guaranteed to run on an unprepared machine has the smallest possible dependency list.

**Azure:** Contributor + User Access Administrator (or Owner) on the target subscription.
**Entra ID:** Global Administrator, for the Entra Kerberos app-registration steps. This is not a Contributor-level operation.

## Check your subscription and tenant

> **Starting from a fresh subscription or tenant?** [`docs/bootstrap.md`](docs/bootstrap.md) is the manual runbook: creating the tenant, elevating access (Global Administrator grants you nothing in Azure), the Security Defaults decision and its 30-day-trial trap, licensing, quota, and the demo group. The script below tells you *what* is wrong; that document tells you *how* to fix it.

Both parameters are required — passing them explicitly means a stale `Az` context can't quietly prepare the wrong subscription.

```powershell
./scripts/Initialize-AvdLabPrerequisites.ps1 `
    -SubscriptionId <your-subscription-guid> `
    -TenantId <your-tenant-guid>
```

Useful switches: `-WhatIf` shows what it would register without registering it; `-OutputPath ./reports/readiness.json` saves the report (write it to `./reports/`, which is gitignored — the report contains your real subscription and tenant IDs); `-Location`, `-VmSize`, and `-SessionHostCount` must match your parameter file if you've changed them, since they drive the quota check.

It **registers** the four required resource providers for you (idempotent, safe to re-run). It **reports** on everything it can't safely fix: vCPU quota, Windows 11 Enterprise multi-session licensing, Entra ID Security Defaults, Conditional Access, MDM auto-enrollment scope, and whether your identity actually holds the roles the deployment needs.

Only one check exits non-zero, and it's the one to read first.

### ⚠️ Security Defaults will stop you

**Entra Kerberos cannot work in a tenant with Security Defaults enabled**, and no script can fix that from the inside.

FSLogix profiles live on an Azure Files share reached via Microsoft Entra Kerberos. Kerberos tickets are acquired silently during user logon — there is no UI to answer an MFA prompt — so the storage account's Entra app must be excluded from MFA. That exclusion is expressible *only* as a Conditional Access policy, Conditional Access requires an Entra ID P1 license, and Security Defaults is all-or-nothing with no per-app exclusion of any kind.

Security Defaults is **enabled by default on every tenant created since October 2019.** If yours has it on, you must consciously disable it and replace it with Conditional Access before the FSLogix half of this lab can work. That's a tenant-wide security decision with real consequences — which is exactly why `Set-AvdLabFSLogixAuth.ps1` detects the condition and refuses to proceed rather than quietly weakening your tenant to make a deployment succeed.

Everything else in the lab — host pool, app group, workspace, autoscale — works fine without it. Only FSLogix profile containers are blocked.

## Deploying a module

There is **no orchestrator yet**. Until `Deploy-AvdLab.ps1` exists, deploy modules one at a time. The parameter file uses `using none`, so compile it and pass each module the parameters it declares:

```powershell
Connect-AzAccount -Subscription <subscription-guid> -Tenant <tenant-guid>
New-AzResourceGroup -Name rg-avdlab-weuc -Location eastus2

# Dry run first. what-if is free and shows you exactly what would change.
New-AzResourceGroupDeployment -ResourceGroupName rg-avdlab-weuc `
    -TemplateFile ./bicep/modules/network.bicep `
    -vnetName vnet-avdlab -vnetCidr 10.20.0.0/24 -subnetCidr 10.20.0.0/26 `
    -WhatIf
```

`bicep/parameters/avdlab.bicepparam` holds placeholder values. Two need real ones before anything deploys:

- **`storageAccountName`** — `stavdlabfslogix` is globally unique across all of Azure and is almost certainly taken. Pick your own.
- **`budgetAlertEmail`** — currently `<YOUR_EMAIL>`.

`.gitignore` already excludes `avdlab.local.bicepparam` and `orchestrator.local.config.json`, and `CONTRIBUTING.md` documents the policy. **Nothing reads those override files yet** — the orchestrator that would prefer them over the tracked defaults isn't written. For now, pass values on the command line as above, and never edit the tracked file with real values.

## Tearing down

Everything lives in one resource group, so teardown is one command. `Remove-AvdLab.ps1` will wrap this with orphan checks; today it's:

```powershell
Remove-AzResourceGroup -Name rg-avdlab-weuc -Force
```

## Verifying your changes

```powershell
az bicep build --file bicep/modules/<module>.bicep --stdout > $null
Invoke-Pester ./tests
```

CI runs both on every push and pull request, plus a full-history `gitleaks` scan. Note the Bicep job treats **warnings as failures**: `az bicep build` exits 0 on a warning, and warnings like `BCP245` mean a resource will not deploy at all — a template that compiles cleanly and silently does nothing is precisely the failure this lab exists to teach people to spot.

## Easy Mode / Hard Mode

**Easy Mode (v1 — this repo)** is the simplest deployable AVD lab that's still a legitimate, real-world-shaped pattern:

- Entra ID-joined session hosts — no AD DS, no Entra Domain Services
- Pooled host pool, Windows 11 Enterprise multi-session, 2–3 hosts with an autoscale scaling plan
- FSLogix profile containers on Azure Files, via Microsoft Entra Kerberos
- Log Analytics workspace + AVD Insights
- Desktop app group, workspace, a single VNet, and a cost guardrail budget alert
- **Zero public IPs and zero inbound RDP rules.** That's not a shortcut taken for demo simplicity — AVD's reverse-connect transport means session hosts only ever make *outbound* HTTPS connections. Nothing ever connects inbound to a session host.
- **A NAT gateway, because outbound is no longer free.** Default outbound access retired on 2026-03-31. VNets created with current API versions get private subnets and no implicit egress, so `network.bicep` sets `defaultOutboundAccess: false` explicitly and supplies a NAT gateway. Left unhandled, the failure is invisible: every deployment succeeds and the host pool sits empty forever, because the AVD agent could never reach the service to register.

Two caveats worth stating plainly. Entra Kerberos support for **cloud-only identities is in Preview** as of July 2026, and Easy Mode depends on it entirely. And the whole build targets **Azure Commercial only** — Azure Government has different endpoints, image availability, and a compliance overlay, so it's a parallel variant rather than a config flag.

It runs happily in a subscription that already has other workloads. Isolation comes from a dedicated resource group, so it never touches anything outside it. An empty subscription is a convenience, never a requirement.

**Hard Mode (roadmap, not built here)** is what it looks like at an actual customer, layered onto the same module foundation: hybrid AD DS join, VNet peering to an existing hub, Private Link with custom DNS, custom golden images, and Intune management (v2). Then Bastion, App Attach, GPU hosts, multi-region DR (v3). Then Azure Local (v4). Azure Government / GCC High is a parallel variant rather than a layer (v5).

Easy Mode's brownfield story is *non-interference*. Hard Mode's is *integration* — peering into a corporate VNet, joining an existing forest, using existing DNS. That's the real distinction between the tiers, not "simple vs. complex."

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — particularly the secrets and leak-prevention norms, and the scope rule that keeps Easy Mode easy.

## License

[MIT](LICENSE)
