# AVD Lab Kit

A fully scripted, repeatable Azure Virtual Desktop lab — "AVD as code." Spin it up, demonstrate the pattern, tear it down cleanly in one command. Bicep modules handle everything that's a clean ARM resource; a thin PowerShell orchestrator wraps them for the things that aren't (Microsoft Graph calls, Microsoft Entra Kerberos enablement, and step-by-step narration you can talk over during a live demo).

This is deliberately the **Easy Mode** build: Entra ID-joined session hosts, no domain controller, no on-prem dependency, one resource group. It's meant to be understood in one sitting and forked without standing up AD DS first. See [Easy Mode / Hard Mode](#easy-mode--hard-mode) for what that leaves out, and why saying so out loud is the point.

## Status

All eight Bicep modules and all seven scripts are written. Every module compiles under `bicep build` with **warnings treated as errors**, every script parses, and the parameter-file guards and leak-prevention tests pass.

**It has not yet been deployed end to end against a live Azure subscription.** Treat it as reviewed code, not as tested infrastructure, until you've run it once yourself. `-Validate` (below) is the cheap way to find out how it behaves in *your* subscription before it creates anything.

## What gets deployed

| Module | What it creates |
| --- | --- |
| `network.bicep` | VNet, subnet, NSG, NAT gateway — no public IP on any session host |
| `storage.bicep` | Azure Files share for FSLogix, with Microsoft Entra Kerberos enabled |
| `hostpool.bicep` | Pooled host pool + a freshly minted registration token |
| `appgroup.bicep` | Desktop application group |
| `workspace.bicep` | Workspace, publishing the application group |
| `sessionhosts.bicep` | N Entra-joined VMs: AVD agent, FSLogix and Kerberos client config |
| `monitoring.bicep` | Log Analytics, AVD diagnostics, data collection rule + agent, budget alert |
| `scalingplan.bicep` | Weekday ramp-up / peak / ramp-down / off-peak autoscale |

| Script | What it does |
| --- | --- |
| `Initialize-AvdLabPrerequisites.ps1` | One-off subscription/tenant readiness check; registers resource providers |
| `Deploy-AvdLab.ps1` | Orchestrates all eight modules, narrating as it goes |
| `Set-AvdLabFSLogixAuth.ps1` | The Entra app-registration work that ARM cannot express |
| `Add-AvdLabAssignments.ps1` | The three role assignments the lab needs to actually work |
| `Test-AvdLabDeployment.ps1` | Smoke test — checks the failures that are otherwise silent |
| `New-AvdLabReport.ps1` | As-built document on success, evidence bundle on failure |
| `Remove-AvdLab.ps1` | Teardown, plus the orphan check a resource group delete doesn't cover |

## Prerequisites

**PowerShell 7+**, and:

```powershell
Install-Module Az.Accounts, Az.Resources, Az.Storage -Scope CurrentUser
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications, `
               Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Users, `
               Microsoft.Graph.Groups -Scope CurrentUser
az bicep install    # or the standalone Bicep CLI, or the VS Code Bicep extension
```

The Bicep CLI is a hard requirement, not just an authoring convenience: `avdlab.bicepparam` uses `using none` and must be compiled before the orchestrator can read it.

`Microsoft.Graph.Applications` and `Microsoft.Graph.Identity.SignIns` are required by `Set-AvdLabFSLogixAuth.ps1`. `Initialize-AvdLabPrerequisites.ps1` deliberately needs neither — it queries the REST endpoints directly, so the one script guaranteed to run on an unprepared machine has the smallest possible dependency list.

**Azure:** Contributor + User Access Administrator (or Owner) on the target subscription. User Access Administrator is not optional — the lab creates role assignments, and granting a role requires the authority to grant roles.

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

Everything else in the lab — host pool, app group, workspace, autoscale — works fine without it. Only FSLogix profile containers are blocked, and `-SkipFSLogix` (below) lets you deploy the rest while you sort it out.

## Configure

Copy both tracked files to their gitignored local overrides and put your real values there. Never edit the tracked copies:

```powershell
Copy-Item bicep/parameters/avdlab.bicepparam bicep/parameters/avdlab.local.bicepparam
Copy-Item orchestrator.config.json orchestrator.local.config.json
```

`Deploy-AvdLab.ps1` prefers the local files automatically whenever they exist. Three values need real ones:

| Where | Value | Why |
| --- | --- | --- |
| `avdlab.local.bicepparam` | `budgetAlertEmail` | Where the cost alert goes. |
| `orchestrator.local.config.json` | `azure.subscriptionId` / `azure.tenantId` | The orchestrator refuses to run on the placeholders. |
| `orchestrator.local.config.json` | `assignment.demoGroupObjectId` | The Entra security group your lab users are in. |

**You no longer pick a storage account name.** It is derived from the lab name plus `uniqueString(resourceGroup().id)` — globally unique without being guessable, and deterministic, so a re-run converges on the same account instead of orphaning one.

### Resource naming

Every resource name derives from a single `labName` (default `lab`), following `<resourceType>-avdlab-<labName>`:

| | |
| --- | --- |
| Host pool | `hp-avdlab-lab` |
| Workspace | `ws-avdlab-lab` |
| Application group | `dag-avdlab-lab` |
| Session hosts | `vm-lab-0`, `vm-lab-1`, … |

Lab names are 3–9 characters, lowercase letters and digits. The ceiling is the 15-character Windows computer name limit: `'vm-' + labName + '-' + a two-digit index`. Changing `labName` deploys a *separate* lab rather than renaming this one, which is what lets several coexist in one subscription.

## Deploying

Dry run first. `-Validate` runs every module through what-if and changes nothing:

```powershell
./scripts/Deploy-AvdLab.ps1 -ResourceGroupName rg-avdlab -Validate
```

Then for real:

```powershell
./scripts/Deploy-AvdLab.ps1 -ResourceGroupName rg-avdlab
```

It runs twelve phases in order, narrating each one, and writes a structured transcript to `./reports/<timestamp>/`. On success it produces an as-built document; on failure it produces an evidence bundle instead — the transcript, the failing deployment's operation detail, and the resource group's state at the point it broke.

`-SkipFSLogix` deploys everything except profile containers. That's the documented fallback: if Entra Kerberos won't cooperate, the host pool, load balancing, autoscale and app group all still work, and profiles simply become local and non-roaming. Losing profiles is much better than losing the whole demo.

Once it finishes, users subscribe at **https://client.wvd.microsoft.com/arm/webclient**. Role assignments take a few minutes to propagate; someone who can't see the desktop immediately is usually waiting on that rather than broken.

## Tearing down

```powershell
./scripts/Remove-AvdLab.ps1 -ResourceGroupName rg-avdlab
```

Everything lives in one resource group, so the delete is a single call. The script then checks what a resource group delete *doesn't* take with it — principally the storage account's Entra application registration, which is a directory object rather than an Azure resource and survives. Add `-RemoveEntraApplication` to clean that up too.

## Troubleshooting

```powershell
./scripts/Test-AvdLabDeployment.ps1 -ResourceGroupName rg-avdlab -HostPoolName hp-avdlab-lab `
    -StorageAccountName <derived-name-from-the-as-built-report> -ExpectedHostCount 3

./scripts/New-AvdLabReport.ps1 -Mode Evidence -ResourceGroupName rg-avdlab
```

Both are read-only and safe against a live environment. The smoke test exists specifically for the failures that report success everywhere else — a host pool with zero registered hosts, a workspace publishing nothing, a scaling plan with no authority to start a VM, a share nobody has RBAC on.

## Verifying your changes

```powershell
bicep build bicep/modules/<module>.bicep --stdout > $null   # or: az bicep build --file ...
Invoke-Pester ./tests
```

CI runs both on every push and pull request, plus a full-history `gitleaks` scan. Note the Bicep job treats **warnings as failures**: `az bicep build` exits 0 on a warning, and warnings like `BCP245` mean a resource will not deploy at all — a template that compiles cleanly and silently does nothing is precisely the failure this lab exists to teach people to spot.

## Easy Mode / Hard Mode

**Easy Mode (this repo)** is the simplest deployable AVD lab that's still a legitimate, real-world-shaped pattern:

- Entra ID-joined session hosts — no AD DS, no Entra Domain Services
- Pooled host pool, Windows 11 Enterprise multi-session, 2–3 hosts with an autoscale scaling plan
- FSLogix profile containers on Azure Files, via Microsoft Entra Kerberos
- Log Analytics workspace + AVD Insights
- Desktop app group, workspace, a single VNet, and a cost guardrail budget alert
- **Zero public IPs and zero inbound RDP rules.** That's not a shortcut taken for demo simplicity — AVD's reverse-connect transport means session hosts only ever make *outbound* HTTPS connections. Nothing ever connects inbound to a session host.
- **A NAT gateway, because outbound is no longer free.** Default outbound access retired on 2026-03-31. VNets created with current API versions get private subnets and no implicit egress, so `network.bicep` sets `defaultOutboundAccess: false` explicitly and supplies a NAT gateway. Left unhandled, the failure is invisible: every deployment succeeds and the host pool sits empty forever, because the AVD agent could never reach the service to register.

One caveat worth stating plainly: the whole build targets **Azure Commercial only**. Azure Government has different endpoints, image availability, and a compliance overlay, so it's a parallel variant rather than a config flag.

Entra Kerberos for cloud-only identities went **generally available on 2026-05-19**, so Easy Mode no longer rests on a preview feature. What GA did *not* change is the fiddly part: admin consent, the `kdc_enable_cloud_group_sids` manifest tag, and the MFA exclusion are all still required, and all three still fail silently when missing. That's what `Set-AvdLabFSLogixAuth.ps1` is for.

It runs happily in a subscription that already has other workloads. Isolation comes from a dedicated resource group, so it never touches anything outside it. An empty subscription is a convenience, never a requirement.

**Hard Mode (roadmap, not built here)** is what it looks like at an actual customer, layered onto the same module foundation: hybrid AD DS join, VNet peering to an existing hub, Private Link with custom DNS, custom golden images, and Intune management. Then Bastion, App Attach, GPU hosts, multi-region DR. Then Azure Local. Azure Government / GCC High is a parallel variant rather than a layer.

Easy Mode's brownfield story is *non-interference*. Hard Mode's is *integration* — peering into a corporate VNet, joining an existing forest, using existing DNS. That's the real distinction between the tiers, not "simple vs. complex."

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — particularly the secrets and leak-prevention norms, and the scope rule that keeps Easy Mode easy.

## License

[MIT](LICENSE)
