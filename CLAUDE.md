# CLAUDE.md — AVD Lab Kit

This file is read automatically by Claude Code at the start of every session in this repo. It contains the full build spec — architecture decisions, module boundaries, build order, and everything already scoped for v1 (Easy Mode).

## How to use this with me (Claude Code)

- Follow the module boundaries and build order below exactly — don't invent new structure.
- v1.0 scope is Section 1. Do not add anything from Section 13 (Hard Mode v2–v5) unless explicitly asked.
- Section 15 is the day-by-day plan — if unsure what to build next, check what date/task we're on there.
- Section 14 (Leak Prevention) rules are non-negotiable: no real subscription/tenant IDs, no hardcoded secrets, placeholders only in tracked files.
- When something in Section 12 (Open Risks) needs verifying against current docs (Kerberos cmdlets, marketplace image SKU), verify it — don't assume the example values in this doc are still current.
- Ask before deviating from this spec; if a decision here seems wrong once we're actually building, flag it rather than silently changing course.

---

# AVD Lab Kit — Build Spec (v1: Easy Mode)

**Purpose:** Fully scripted, repeatable Azure Virtual Desktop lab for the WEUC community presentation in September. Goal is "AVD as code" — spin up live (or pre-staged), demonstrate the pattern, tear down cleanly after the session.

**Audience:** WEUC community members. Assume the code itself may be shown/discussed on screen — write it clean enough to publish to GitHub alongside slides (same pattern as the AVD Current State Collector repo).

**Architecture pattern:** Bicep modules for all declarative infrastructure, with a thin PowerShell orchestrator wrapped around it for anything that isn't a clean ARM resource — Graph calls, FSLogix/Azure AD Kerberos enablement, and live-demo narration.

---

## 0. Easy Mode / Hard Mode Concept

**AVD Lab Kit is being designed as a two-tier project from the start:**

- **Easy Mode (v1 — this spec, target: September WEUC presentation)** — the simplest deployable AVD lab that's still a legitimate, real-world-shaped pattern. Entra ID join only, no on-prem dependencies, small autoscaled pool, one Resource Group, tear down in one command. Built to be demoed live, understood in one sitting, and forked by anyone in the audience without needing a domain controller or AD sync running first.
- **Hard Mode (v2/v3/v4/v5 — roadmap, not built now)** — the harder, more "how it actually looks at a customer" scenarios layered on top of the same Bicep module foundation: hybrid AD DS join, Private Link/custom DNS, custom golden images (v2); GPU hosts, App Attach, multi-region/DR, Bastion (v3); Azure Local/hybrid infrastructure (v4); a complete Azure Government/GCC High variant (v5, parallel rather than layered). Section 13 captures all tiers as a running list so they have a home without pulling scope into v1.

Keeping these explicitly separate means Easy Mode never quietly grows scope creep from "well, while we're in here…" — anything that smells like Hard Mode gets parked in Section 13 instead of bolted onto the September build.

**Easy Mode's brownfield story is non-interference, not emptiness.** It's designed to work in an existing subscription with other workloads already running — isolation via a dedicated Resource Group means it never touches anything outside it, so it doesn't require a greenfield/empty subscription. Hard Mode's eventual brownfield story is a different, harder problem: *integration* — peering into an existing corporate VNet, joining an existing AD forest, existing DNS — worth stating out loud as the actual distinction between the two tiers, not "simple vs. complex" alone.

---

## 1. Scope & Non-Goals (v1 — Easy Mode)

**In scope:**
- Entra ID-joined session hosts (no AD DS, no Entra Domain Services)
- Pooled host pool, Windows 11 Enterprise multi-session
- 2–3 session hosts with an autoscale scaling plan
- FSLogix profile containers on Azure Files
- Azure Monitor / Log Analytics Workspace + AVD Insights (diagnostic settings, Data Collection Rule/AMA on session hosts)
- Desktop app group + workspace, single VNet
- Full teardown

**Subscription assumption:** works in either a greenfield (empty) or brownfield (existing workloads) subscription — isolation via a dedicated Resource Group means no interference with anything already there. An empty subscription is a convenience, never a requirement; see Section 3 for the pre-flight checks that matter regardless of which kind of subscription it is.

**Cloud environment:** targets **Azure Commercial** only. Azure Government (GovCloud/GCC High) is not a configuration option for v1 — it's a complete separate variant with its own endpoints, image availability, and compliance overlay. See Section 13 (v5).

**Explicitly deferred to Hard Mode (see Section 13) — not built in v1:**
- Hybrid identity / AD DS extension scenarios
- VNet peering / on-prem connectivity (VPN Gateway, ExpressRoute, hub-and-spoke)
- Intune management (compliance policies, configuration profiles, security baselines, Win32 app deployment)
- Multi-region or DR
- Azure Local / Azure Hybrid infrastructure (Azure Stack HCI)
- Azure Government / GCC High (a separate cloud variant, not a v1 config option — see Cloud environment above and Section 13 v5)
- Production-grade hardening (Private Link, custom DNS, Conditional Access build-out)
- Custom golden images, App Attach, GPU/graphics workloads

Calling this out to the audience directly is a feature, not a caveat — "here's the easy path, and here's what gets harder" is a stronger talk structure than pretending this is the whole story.

---

## 2. Key Architecture Decisions

| Decision | Choice | Why |
|---|---|---|
| IaC approach | Bicep modules, one per resource type | Native idempotency, `what-if` support, reusable artifact for the audience |
| Orchestration | Thin PowerShell wrapper, sequential deployments | Keeps live-demo narration ("Creating host pool… registering host 2 of 3…") that a single monolithic template can't give you |
| Identity | Entra ID Join only | Simplest audience-facing story, no domain controller to explain/build — this *is* the Easy Mode line in the sand. Genuinely Intune-free by design: MDM enrollment is a separate, optional tenant-level setting, not a dependency of Entra join itself (see Section 3 pre-flight check) |
| Host pool type | Pooled, multi-session | Matches "small pool with autoscale" |
| Session host count | 2–3 | Enough to show load balancing + autoscale without burning demo time |
| Session host OS | Win11 Enterprise multi-session, marketplace image | Fastest path; custom image is a Hard Mode item |
| Profile management | FSLogix on Azure Files | Standard for pooled — **see Section 6, the one non-trivial config item** |
| Monitoring | Log Analytics Workspace + AVD Insights | Standard expectation even for a lab; self-contained, no Intune/AD dependency |
| Scaling plan | Ramp-up/peak/ramp-down/off schedule | Visual, easy to narrate live |
| Networking | Single VNet/subnet + NSG + NAT gateway, no public IP on any session host | No on-prem, no VPN/ExpressRoute needed since there's no AD DS. Session hosts have zero public IP and zero inbound NSG rule for RDP — AVD's reverse-connect transport means only outbound HTTPS (443) to the AVD service/Entra ID/Azure Files is required; there's no inbound connection to a session host at any point. **Outbound is no longer free, though:** since the API versions released after 2026-03-31, new VNets default to private subnets (`defaultOutboundAccess: false`) and Azure no longer grants implicit egress. Without an explicit path the AVD agent can't register and the pool comes up empty. A NAT gateway supplies it — outbound only, and it owns the lab's single public IP. `defaultOutboundAccess` is set explicitly in `network.bicep` rather than inherited, so behavior doesn't silently change with the apiVersion string |
| App group | Desktop app group | Simplest for demo; RemoteApp as an optional stretch goal |
| Resource scoping | Everything in one Resource Group | Teardown = one `Remove-AzResourceGroup` call |
| Subscription assumption | Brownfield-safe via dedicated RG isolation | Works alongside existing resources; no VNet peering or naming assumptions that would require an empty subscription |
| Cloud environment | Azure Commercial | GovCloud/GCC High has different endpoints, marketplace availability, and a compliance overlay — treated as a complete separate variant (Section 13, v5), not a config toggle on this build |
| Cost guardrail | Azure Budget + action group email alert, scoped to the RG (`costGuardrailMode` parameter, default `AlertOnly`) | Alerts on runaway spend without auto-deleting a possibly-live environment by default. An `AlertAndDelete` mode exists as a design (Section 18) using an Automation Runbook, deferred to v1.x — the parameter ships in v1.0 as a no-op default, the actual delete mechanism doesn't |

---

## 3. Prerequisites

**Tooling:**
- PowerShell 7+
- Az PowerShell modules: `Az.Accounts`, `Az.Resources` (covers Bicep deployment via `New-AzResourceGroupDeployment -TemplateFile *.bicep` — no separate az CLI dependency needed), `Az.Storage` (share verification in `Test-AvdLabDeployment.ps1`, and the imperative fallback for the Section 6 Kerberos toggle)
- Bicep CLI/VS Code extension for authoring and local linting (`az bicep install`, or VS Code Bicep extension)
- Microsoft Graph PowerShell SDK: `Microsoft.Graph.Authentication`, `Microsoft.Graph.Users`, `Microsoft.Graph.Groups` (demo user/group assignment), `Microsoft.Graph.Applications` + `Microsoft.Graph.Identity.SignIns` (the Section 6 app-registration and Conditional Access work in `Set-AvdLabFSLogixAuth.ps1`)

> `Initialize-AvdLabPrerequisites.ps1` deliberately needs none of the Graph SDK beyond `Microsoft.Graph.Authentication`, and no `Az.Compute` — it issues its checks through `Invoke-MgGraphRequest`/`Invoke-AzRestMethod` rather than the typed cmdlets. Making someone install three extra modules before a *prerequisite checker* will start is a poor first impression, and it's the one script guaranteed to run on a machine that has never touched this project.

**Azure:**
- Subscription with Contributor + User Access Administrator (or Owner) on the target RG

**Entra ID:**
- Global Admin or equivalent role available for the Azure AD Kerberos step (Section 6) — confirm ahead of time, this is not a Contributor-level operation

**Licensing:**
- Confirm the demo tenant has Windows 11 Enterprise multi-session use rights (M365 E3/E5, Windows E3/E5, or a dev/test subscription with included licensing) — flag this now, don't discover it night-of

**Pre-flight checks (same list regardless of greenfield vs. brownfield — see Section 0/1):**
- Resource provider registration: `Microsoft.DesktopVirtualization`, `Microsoft.Compute`, `Microsoft.Network`, `Microsoft.Storage` — a clean/greenfield subscription is sometimes *more* likely to be missing these than one that's already used other Azure services
- vCPU quota for the session host VM family/region against configured VM size × session host count — usually cuts the other way: a brownfield subscription already running workloads is more likely to be quota-constrained
- Azure Policy inherited from a management group (mandatory tags, allowed regions/SKUs, required NSG rules) — the one item genuinely more likely in a brownfield enterprise subscription than a personal sandbox, and the one most likely to block a live deployment partway through if not surfaced first
- Whether the demo tenant already has MDM auto-enrollment turned on for Entra ID-joined Windows devices — if it is, session hosts will silently enroll into Intune during the demo regardless of anything Lab Kit does (Intune management itself is a Hard Mode item, Section 13). This is a fact about the tenant's MDM user scope setting, not a gap in Lab Kit's design — Entra ID join has no Intune dependency, so the build stays genuinely Intune-free as long as the tenant's scope allows it; worth knowing ahead of time either way so it isn't a confusing surprise on stage
- Existing Conditional Access policies (or Entra ID Security Defaults) in the demo tenant — **this is a blocking check, not a courtesy one.** *AVD sign-in* has no architectural dependency on CA (RBAC alone handles access; building out CA policies is correctly a Hard Mode item, Section 13). *FSLogix on Entra Kerberos does*: the storage account app must be excluded from any MFA requirement, which is only expressible as a Conditional Access exclusion. So a tenant on Security Defaults cannot run this build at all until Security Defaults is turned off and replaced with CA (Section 6/12/19), and a tenant already on CA needs the exclusion added. Separately, an existing MFA requirement means the demo account needs MFA registered before presentation day, and a narrowly-scoped CA policy excluding the Azure Virtual Desktop service principal could block sign-in for reasons unrelated to anything Lab Kit built

---

## 4. Solution Structure

```
/AvdLabKit
  /bicep
    /modules
      network.bicep          # VNet, subnet, NSG, NAT gateway — no public IP on any session host, no inbound rules (explicit outbound egress, see Section 2)
      hostpool.bicep          # host pool + @secure() registration token output (via listRegistrationTokens())
      appgroup.bicep          # desktop app group; deploys BEFORE workspace (see orchestrator step 6)
      workspace.bicep         # workspace; takes the app group ID and publishes it
      storage.bicep           # storage account + FSLogix share, incl. directoryServiceOptions: 'AADKERB' (Bicep-native — see Section 6)
      sessionhosts.bicep      # N VMs, no public IP, AADLoginForWindows extension, AVD agent/boot loader install
      monitoring.bicep        # Log Analytics Workspace (30-day default retention, scoped diagnostic categories — Section 7), AVD diagnostic settings, DCR + AMA on session hosts, Azure Budget + action group email alert (cost guardrail — alert only, not auto-teardown)
      scalingplan.bicep
    /parameters
      avdlab.bicepparam       # single source of truth for all resource parameters
  /scripts
    Deploy-AvdLab.ps1         # orchestrator — calls modules in sequence, narrates progress
    Initialize-AvdLabPrerequisites.ps1 # greenfield setup runbook — run once, up front (Section 19)
    Remove-AvdLab.ps1         # teardown
    Set-AvdLabFSLogixAuth.ps1 # post-Kerberos Entra app registration fixups — Graph, not ARM (Section 6)
    Add-AvdLabAssignments.ps1 # Graph calls — assign demo users/groups to app group; plus the Storage File Data SMB Share Contributor role assignment the FSLogix share needs (Section 6)
    Test-AvdLabDeployment.ps1 # smoke test after deployment
    New-AvdLabReport.ps1      # as-built doc on success, evidence bundle on failure/on-demand (Section 17)
  /tests
    AvdLab.Tests.ps1          # Pester — parameter validation + `az bicep build` lint check
  orchestrator.config.json    # settings the PowerShell layer needs that aren't Bicep parameters (demo group object ID, narration on/off, timing)
  README.md                   # see the README structure outline below
  CONTRIBUTING.md              # secrets/leak-prevention norms (Section 14), contribution guidance for Hard Mode tiers
```

**Orchestrator responsibilities (`Deploy-AvdLab.ps1`):**
1. `Connect-AvdLabContext` — connect Az + Graph, validate subscription/tenant context, fail fast if wrong; run subscription pre-flight checks (resource provider registration, vCPU quota, Azure Policy surfacing — Section 3) before any deployment starts
2. Deploy `network.bicep` → log step, deploy, capture outputs
3. Deploy `storage.bicep` → capture storage account name/share
4. Run `Set-AvdLabFSLogixAuth.ps1` (Azure AD Kerberos enablement — see Section 6)
5. Deploy `hostpool.bicep` → capture registration token output (a `@secure()` output, obtained via `listRegistrationTokens()` — `registrationInfo.token` is write-only and a GET never returns it)
6. Deploy `appgroup.bicep`, **then** `workspace.bicep` — this order is reversed from the original spec on purpose. The workspace↔app-group link is stored on the *workspace* as `applicationGroupReferences`, so creating the workspace first would mean deploying it twice: once empty, once with the reference. Building the app group first and passing its ID into `workspace.bicep` links them in one pass, with no window where the workspace exists publishing nothing
7. Deploy `sessionhosts.bicep`, passing the registration token as a parameter
8. Deploy `monitoring.bicep` — Log Analytics Workspace, AVD diagnostic settings, DCR/AMA association to session hosts
9. Deploy `scalingplan.bicep`, associate to host pool
10. Run `Add-AvdLabAssignments.ps1` — Graph calls to assign demo users/groups
11. Run `Test-AvdLabDeployment.ps1` — smoke test
12. Run `New-AvdLabReport.ps1 -Mode AsBuilt` — generate the as-built document from the structured deployment log (Section 17). On any failure earlier in the sequence, the catch block runs `New-AvdLabReport.ps1 -Mode Evidence` instead
13. Print summary (host pool URL, workspace name, resource group)

Each step is a discrete `New-AzResourceGroupDeployment` call rather than one giant `main.bicep` — that's what preserves the "watch it build, phase by phase" quality for the live demo, while still getting Bicep's idempotency and diff-ability at each phase.

**README.md structure:**
1. **What this is** — one-paragraph pitch, pointer to the Easy Mode/Hard Mode framing (Section 0)
2. **Prerequisites / Getting Started** — the high-level setup steps, in order:
   - Confirm tooling: PowerShell 7+, Az PowerShell modules, Bicep CLI, Microsoft Graph SDK (Section 3)
   - Run `Initialize-AvdLabPrerequisites.ps1` against your target subscription/tenant (Section 19) — auto-registers resource providers, reports quota/licensing/Security Defaults/MDM-scope/RBAC gaps
   - Resolve anything it flags manually before proceeding — licensing procurement, a quota increase request, registering MFA on the account you'll demo with — none of these are things a script can do for you
   - Fill in your local, gitignored parameter override file with real values (Section 14) — never edit the tracked `avdlab.bicepparam` directly
3. **Deploying** — running `Deploy-AvdLab.ps1`, what `-WhatIf`/`-Confirm` does for a dry run, what to expect on success (the as-built report, Section 17)
4. **Tearing down** — `Remove-AvdLab.ps1`
5. **Troubleshooting** — pointing to `New-AvdLabReport.ps1 -Mode Evidence` (Section 17) for anything that broke
6. **Easy Mode / Hard Mode** — what's built (Section 0/1), what's roadmapped (Section 13), so a reader knows what they're looking at without digging through this spec
7. **Contributing** — pointer to `CONTRIBUTING.md`

---

## 5. Idempotency & Error Handling

- **Bicep handles resource-level idempotency natively** — re-running a module deployment converges to the declared state rather than erroring on "already exists." This removes essentially all of the manual `Get-Az*`-before-`New-Az*` boilerplate a pure-PowerShell version would need.
- Orchestrator wraps every deployment call in try/catch, logs via a central `Write-Log` function (console + a structured, machine-parseable transcript — timestamp, step name, status, resource IDs/outputs, not just plain text), and checks the deployment result object before proceeding to the next phase — if phase 3 fails, phase 4 shouldn't run. On failure, the catch block triggers `New-AvdLabReport.ps1 -Mode Evidence` (Section 17) instead of just exiting.
- `-WhatIf` is supported per-deployment (`New-AzResourceGroupDeployment -WhatIf`) — expose this as a `-Validate` switch on the orchestrator for a full dry-run rehearsal before the actual presentation, without needing a separate CLI tool.
- Random local admin password generated at runtime for session host provisioning (never hardcoded), discarded after — Entra join removes the long-term need for it.

---

## 6. FSLogix + Entra ID Join — the one item to de-risk early

Because there's no AD DS or Entra Domain Services in this design, FSLogix profile access to Azure Files depends on **Microsoft Entra Kerberos for Azure Files**, not traditional Kerberos.

> **Verified against live docs 2026-07-09 — this section was rewritten as a result.** The original spec assumed Kerberos enablement was not an ARM resource property and had to be scripted. That is no longer true. The boundary moved; the risk did not disappear, it relocated.

**Bicep-native (`storage.bicep`)** — storage account, SMB settings, share creation, network rules, *and the Kerberos toggle itself*:

```bicep
properties: {
  azureFilesIdentityBasedAuthentication: {
    directoryServiceOptions: 'AADKERB'   // valid on API 2025-01-01 → 2026-04-01
  }
}
```

For cloud-only identities (which is what Easy Mode uses), no `activeDirectoryProperties` block is needed — `domainName`/`domainGuid` are only required for hybrid identities configuring ACLs through File Explorer. Keeping this declarative means a re-run converges instead of silently drifting, which is the whole reason the rest of the build is Bicep.

`Set-AzStorageAccount -EnableAzureActiveDirectoryKerberosForFile $true` still exists in current `Az.Storage` and remains a valid imperative fallback if the ARM property misbehaves on the day.

**Not Bicep-native (`Set-AvdLabFSLogixAuth.ps1`)** — enabling the toggle creates an Entra app registration for the storage account, and three things must then be done *to that app registration*. All are Microsoft Graph, all need Global Admin, none are ARM resources:

1. **Grant admin consent** to the new service principal — lets users request Entra tokens for the storage account.
2. **Exclude the storage account's service principal from MFA.** Kerberos ticket acquisition happens silently during user logon; there is no UI to satisfy a step-up prompt. Without the exclusion, mounting the share fails with `System error 1327: Account restrictions are preventing this user from signing in`.

   > **Security Defaults is a hard blocker, not a hurdle — verified 2026-07-09.** An earlier revision of this section said the exclusion "is not optional" when Security Defaults is on, implying it's a step you perform anyway. **You cannot perform it at all.** Excluding an app from an MFA requirement is a Conditional Access operation; Conditional Access requires Entra ID P1; and Security Defaults is all-or-nothing by design, exposing no per-app or per-user exclusion (the sole documented exception is the Directory Synchronization Accounts role). A tenant running Security Defaults **cannot host a working Entra Kerberos FSLogix share**, full stop.
   >
   > The remedy is tenant-level and deliberate: disable Security Defaults, then replace it with Conditional Access policies that exclude the storage account app. `Set-AvdLabFSLogixAuth.ps1` detects this condition, explains it, and stops — it will not silently weaken a tenant's security posture to make a lab deploy. Note that Security Defaults is **on by default for new tenants**, so the greenfield path in Section 19 hits this wall every time, not occasionally.
3. **Add the `kdc_enable_cloud_group_sids` app manifest tag.** *Mandatory for cloud-only identities.* Without it, Entra issues Kerberos tickets that omit cloud-only group SIDs, and share permissions granted to an Entra group will not resolve. This is the step most likely to fail quietly on stage, because everything looks correctly configured right up until a profile fails to load. Note the Graph `tags` collection is **replace-in-full** — read the existing tags and merge, never assign, or you silently drop whatever Azure already stamped on the app.

**Share-level authorization (`Add-AvdLabAssignments.ps1`)** — for cloud-only identities there are no NTFS ACLs in the picture at all: access to the share is governed *entirely* by Azure RBAC. The demo group needs `Storage File Data SMB Share Contributor` scoped to the storage account, or profiles fail to load even with all three Graph steps above done correctly. Grouped with the app-group assignment rather than in `storage.bicep` because it's keyed on the demo group's object ID, which lives in `orchestrator.config.json` (Section 7) — putting it in Bicep would drag a real directory object ID into the tracked parameter file that Section 14 requires stay free of them.

**Client-side (`sessionhosts.bicep`, via Custom Script Extension)** — two registry values on every session host, plus FSLogix's own `Enabled` / `VHDLocations`:

- `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters\CloudKerberosTicketRetrievalEnabled = 1`
- `HKLM\Software\Policies\Microsoft\AzureADAccount\LoadCredKeyFromProfile = 1`

Two Windows services must also be running on every session host — verify, don't assume, since a hardening baseline may have disabled them:

- `WinHttpAutoProxySvc` (WinHTTP Web Proxy Auto-Discovery) — carries the KDC Proxy requests Kerberos ticket retrieval depends on. WPAD itself can be disabled via registry for security; the *service* must not be.
- `iphlpsvc` (IP Helper)

FSLogix itself ships pre-installed on the Windows Enterprise multi-session marketplace images — it only needs configuring, not installing.

Before building the rest of the solution:
- **Cloud-only identity support for Entra Kerberos is in Preview** (verified 2026-07-09), as is the `kdc_enable_cloud_group_sids` tag that goes with it. Easy Mode's entire identity story rests on it. Not a blocker, but state it out loud — on stage, in the README, and to anyone forking this — rather than letting an audience assume GA. Re-check its status at the Section 18 drift check; if it went GA between now and September, that's a good slide, and if it changed shape, that's a rebuild.
- Confirm your target region supports Entra Kerberos for Azure Files. Note the cloud-only identity path is **Azure Commercial only** — which is consistent with Section 1's Commercial-only scope, and is a further reason GovCloud (Section 13, v5) is a parallel variant rather than a config flag.
- **The RC4 → AES-SHA1 Kerberos hardening already shipped** in the April 2026 Windows update. This is a live constraint today, not a future one: file shares hosting FSLogix containers that weren't upgraded to AES-SHA1 have access issues. Build on AES-SHA1 from the start.
- Have a fallback for the live demo: if Kerberos auth won't cooperate on stage, a local-profile fallback (no FSLogix) still lets the rest of the demo (host pool, autoscale, app group) run without a blocked dependency.

Prototype the **Graph steps** in isolation first. The Bicep toggle is now boring; the app-registration fixups are where the pre-presentation buffer time actually goes.

---

## 7. Parameters

**`avdlab.bicepparam`** drives everything Bicep needs.

> **Corrected 2026-07-09 — the original `using 'modules/network.bicep'` form does not compile.** A `.bicepparam` binds to exactly one template and may only assign parameters that template declares; a single file spanning eight modules is rejected with `BCP259` ("assigned in the params file without being declared in the Bicep file"). Verified against Bicep CLI 0.44.1.
>
> The file therefore uses **`using none`**, which decouples it from any template and compiles standalone to a `deploymentParameters` JSON document. `Deploy-AvdLab.ps1` reads that document and passes each module only the parameters that module declares, via `-TemplateParameterObject`. Section 7's "single source of truth" survives intact; what's lost is compile-time type checking of values against modules, so a typo'd name would be silently ignored rather than rejected. `tests/AvdLab.Tests.ps1` closes that hole with four guards: the file compiles, every assigned name is declared by some module (or explicitly listed as belonging to a not-yet-built one), no name ambiguous across modules is assigned, and no runtime-injected value is pinned.
>
> **Name collisions are the non-obvious hazard of a flat file.** Parameter names are module-scoped: `friendlyName` means three different things in `hostpool.bicep`, `appgroup.bicep`, and `workspace.bicep`, so assigning it once would splat one string into all three. Only lab-wide values (`location`, `tags`) or unambiguously-named ones belong here. Anything whose name repeats with a different meaning is omitted and left to each module's default — the Pester suite enforces this.
>
> Two naming notes: the storage parameters are `storageAccountName`/`shareName` (matching what `storage.bicep` declares) rather than the `fslogixStorageAccountName`/`fslogixShareName` this section originally showed — with a splat, the names must match the module's. And `resourceGroupName` is not a Bicep parameter at all; it's a deployment scope the orchestrator supplies.

```bicep
using none

param location = 'eastus2'
param vnetName = 'vnet-avdlab'
param vnetCidr = '10.20.0.0/24'
param subnetCidr = '10.20.0.0/26'
param hostPoolName = 'hp-avdlab-pooled'
param workspaceName = 'ws-avdlab'
param appGroupName = 'dag-avdlab'
param sessionHostCount = 3
param vmSize = 'Standard_D4ads_v5'
param imagePublisher = 'MicrosoftWindowsDesktop'
param imageOffer = 'windows-11'
param imageSku = 'win11-25h2-avd' // verified 2026-07-09. Supported to 2028-10-10. Alternative: win11-24h2-avd (to 2027-10-12). Do NOT use win11-23h2-avd — end of updates 2026-11-10, i.e. weeks after the September demo. Re-verify during the Section 18 drift check.
param fslogixStorageAccountName = 'stavdlabfslogix'
param fslogixShareName = 'profiles'
param logAnalyticsWorkspaceName = 'log-avdlab-weuc'
param logAnalyticsRetentionDays = 30 // free-tier default; deliberately not extended — this is a short-lived lab, not a production workspace (Section 18)
param budgetAmount = 50 // adjust to your own comfort threshold; alert-only, see Section 2 cost guardrail row
param budgetAlertEmail = '<YOUR_EMAIL>' // placeholder — real value goes in the local gitignored override, never the tracked file (Section 14)
param costGuardrailMode = 'AlertOnly' // 'AlertOnly' (v1.0 default, no-op beyond the budget alert) or 'AlertAndDelete' (Automation Runbook mechanism, Section 18 — not built until v1.x)
```

**`orchestrator.config.json`** holds the handful of settings that are purely for the PowerShell layer, not Bicep parameters — things like the demo user/group object ID for Graph assignment, a narration on/off toggle, and scaling plan schedule times if you want those editable without touching Bicep directly.

**Diagnostic category scoping (`monitoring.bicep`):** enable `Checkpoint`, `Error`, `Management`, `Connection`, `HostRegistration`, and `AgentHealthStatus` — the categories AVD Insights actually needs. Leave `NetworkData` and `ConnectionGraphicsData` off by default; they're higher-volume and matter more for production performance troubleshooting than a short-lived demo lab. Realistically, ingestion cost for a few hosts over a few hours is negligible regardless of category choice — the actual cost exposure is *how long the environment stays running*, which is what the Section 2 budget alert is for, not the diagnostic category list.

Naming convention: `<resourceType>-avdlab-<qualifier>` across both layers — keeps everything greppable and matches the style in your other GitHub repos.

---

## 8. Demo-Specific Considerations

- Build two run modes: a **full from-scratch build** (deep technical walkthrough) and a **fast/pre-staged** path using a custom image with AVD agent + FSLogix pre-installed (when demo time is tight)
- Narrate-friendly logging: step names should read naturally out loud ("Deploying network module… Registering session host 1 of 3…")
- Have a pre-built fallback environment ready in case live deployment hiccups mid-session — don't let the talk depend on a live Azure control-plane response
- `-Validate` switch (Section 5) lets you rehearse the talk track against `what-if` output without touching Azure
- Consider a slide or two framing the Easy Mode/Hard Mode split up front — it sets audience expectations and gives you a natural close ("if you want to see Hard Mode, that's a future session")
- The as-built report generated at the end of a successful run (Section 17) doubles as a genuine audience takeaway — "here's the document it just produced" — rather than console scrollback that's gone once the terminal closes
- Zero public IP / no inbound RDP anywhere in the design (Section 2) is worth calling out explicitly to the audience — it's not a security corner cut for the sake of a simple demo, it's literally how AVD's reverse-connect transport works, and a good moment to correct a misconception some attendees may still have from pre-2019 RDP-based remote desktop patterns
- **The NAT gateway is a deliberate talking point, not an implementation detail.** Default outbound access retired on 2026-03-31; VNets created with current API versions get private subnets and no implicit egress. Plenty of the audience still has templates that "just worked" and will quietly stop working the next time they bump an apiVersion — the failure mode is a host pool that deploys successfully and then sits empty, because the agent never reached the service to register. Pairs naturally with the reverse-connect beat above: one slide on "nothing gets in," one on "and getting out is now something you have to ask for." Show `defaultOutboundAccess: false` set explicitly and explain why inheriting the default is the actual trap

---

## 9. Testing Plan

- **Unit:** Pester tests for parameter file validation + `az bicep build` (or `Test-AzResourceGroupDeployment`) as a lint/compile check per module
- **Integration:** full deploy in a test subscription, timed, to confirm it fits your demo window
- **Teardown verification:** confirm `Remove-AzResourceGroup` leaves nothing orphaned (Key Vault soft-delete, if used, is the usual culprit)

---

## 10. Suggested Build Order

1. `network.bicep` — VNet/subnet/NSG
2. `storage.bicep` + `Set-AvdLabFSLogixAuth.ps1` — **prototype the Kerberos step in isolation first** (Section 6)
3. `hostpool.bicep`, `workspace.bicep`, `appgroup.bicep` — scaffolding, no hosts yet
4. `sessionhosts.bicep` — Entra join + AVD agent + registration
5. `monitoring.bicep` — Log Analytics Workspace, diagnostic settings, DCR/AMA (needs session hosts to exist for the AMA association)
6. `scalingplan.bicep`
7. `Add-AvdLabAssignments.ps1` + `Test-AvdLabDeployment.ps1`
8. `Remove-AvdLab.ps1` + full dry-run rehearsal

---

## 11. Deliverables Checklist (v1 — Easy Mode)

- [ ] `/bicep/modules/*.bicep` (network, hostpool, workspace, appgroup, storage, sessionhosts, monitoring, scalingplan)
- [ ] `avdlab.bicepparam`
- [ ] `Deploy-AvdLab.ps1`
- [ ] `Initialize-AvdLabPrerequisites.ps1`
- [ ] `Set-AvdLabFSLogixAuth.ps1`
- [ ] `Add-AvdLabAssignments.ps1`
- [ ] `Test-AvdLabDeployment.ps1`
- [ ] `New-AvdLabReport.ps1`
- [ ] `Remove-AvdLab.ps1`
- [ ] `orchestrator.config.json`
- [ ] `README.md` (usage, prereqs, talk-track outline, Easy Mode/Hard Mode framing)
- [ ] `CONTRIBUTING.md`
- [ ] Pester test file
- [ ] Rehearsal run completed in a test subscription, timed

---

## 12. Open Risks to Resolve Before Coding

- ~~Azure AD Kerberos for FSLogix: regional availability + current Az module cmdlet support~~ — **RESOLVED 2026-07-09.** The toggle is an ARM property (`directoryServiceOptions: 'AADKERB'`), not a cmdlet-only operation; `Set-AzStorageAccount -EnableAzureActiveDirectoryKerberosForFile` remains as a fallback. Section 6 rewritten. Residual risk moved to the three Graph app-registration steps, of which `kdc_enable_cloud_group_sids` (mandatory for cloud-only) was missing from the original spec entirely.
- ~~Marketplace image SKU name~~ — **RESOLVED 2026-07-09.** `win11-25h2-avd`. See Section 7. Still re-verify at the Section 18 drift check.
- **NEW: RC4 → AES-SHA1 Kerberos hardening already shipped** (April 2026 Windows update). Not a future risk — a present constraint on the FSLogix file share. Confirm the share is on AES-SHA1.
- ~~Session hosts have no outbound path~~ — **RESOLVED 2026-07-09.** Default outbound access retired 2026-03-31; new VNets default to private subnets. `network.bicep` now deploys a NAT gateway and sets `defaultOutboundAccess: false` explicitly. Left unhandled this would have failed *silently*: every deployment succeeds, and the host pool simply never registers a host. Worth re-testing at the Section 18 drift check, since it's invisible in `what-if`.
- ~~**Security Defaults makes Entra Kerberos impossible**~~ — **MITIGATED 2026-07-09 by the disposable-tenant decision below.** The finding stands (the MFA exclusion is a Conditional Access operation needing Entra ID P1; Security Defaults offers no exclusion mechanism at all, and is on by default for every tenant created since Oct 2019), but the remedy is now settled rather than open. `Set-AvdLabFSLogixAuth.ps1` still detects and refuses rather than remediating. See Section 6 and `docs/bootstrap.md`.
- ~~**Licensing confirmation for Win11 Enterprise multi-session in the demo tenant**~~ — **RESOLVED 2026-07-09** by the same decision: an Azure Dev/Test subscription includes AVD access rights for acceptance testing with no per-user entitlement, and `Initialize-AvdLabPrerequisites.ps1` detects it from the subscription's `quotaId`.

### DECISION 2026-07-09 — the demo tenant is disposable

Created for this lab, holds no real data, deleted afterwards. It therefore takes **Path A** in `docs/bootstrap.md`: **Security Defaults disabled, and no Conditional Access policies at all.** Nothing enforces MFA, so nothing blocks the silent Kerberos ticket acquisition FSLogix depends on, and `Set-AvdLabFSLogixAuth.ps1` reports "No Conditional Access policies found; nothing to exclude" and proceeds.

Why this is the right call for a lab kit rather than a corner cut:

- **It needs no Entra ID license.** Conditional Access requires P1+. The P2 trial lasts **30 days** — started in July to unblock the build, it expires in early August, weeks before the September demo. Worse, CA policies are *not* disabled when a license lapses: they keep enforcing and become read-only, so an expired trial would leave an MFA-for-all-apps policy still blocking Kerberos that you can no longer add an exclusion to.
- **It removes the licensing risk too.** Paired with a Dev/Test subscription, the Win11 multi-session entitlement question disappears.
- **It is honest about the tradeoff.** A tenant with no MFA is only acceptable *because* it is disposable — no real accounts, no real data, strong unique admin password, short life. This is a property of the demo tenant, not a recommendation Lab Kit makes about anyone's production tenant, and the README and bootstrap doc both say so.

Anyone forking Lab Kit into a tenant they care about takes Path B instead. Nothing in the code assumes Path A; `Set-AvdLabFSLogixAuth.ps1` handles both, and `-ApplyConditionalAccessExclusion` exists precisely for Path B.
- **NEW: Cloud-only identity support for Entra Kerberos is in Preview** (verified 2026-07-09). Easy Mode depends on it entirely. Disclose it rather than implying GA; re-check status at the Section 18 drift check.
- **NEW: Share access for cloud-only identities is pure Azure RBAC** — no NTFS ACLs are involved. The demo group needs `Storage File Data SMB Share Contributor` on the storage account or profiles fail to load with everything else configured correctly. This was missing from the original spec's module/script responsibilities entirely; it now lives in `Add-AvdLabAssignments.ps1` (Section 6).
- **NEW: Two session-host services are Kerberos prerequisites** — `WinHttpAutoProxySvc` (carries KDC Proxy requests) and `iphlpsvc` must both be running. The original spec listed only the two registry values. Verify in `sessionhosts.bicep`'s CSE.
- Custom image vs. marketplace image tradeoff — decide based on how tight the live demo window actually is
- Budget alert needs a real recipient — decide whose email goes in the gitignored local override for `budgetAlertEmail` before the first deployment, not after

---

## 13. Hard Mode Roadmap (v2 / v3 / v4 / v5 — not in scope for September)

Parked here so Easy Mode stays Easy Mode. Split into tiers: **v2** is the core "how it actually looks at a customer" integration scenarios — the harder architecture decisions that change how Lab Kit connects to the outside world. **v3** is further out — optional, layered additions (workload variants, geographic scale, operational convenience) that only make sense once v2 exists. **v4** is a fundamentally different infrastructure model, not just a layered addition on top of v2/v3. **v5** is different again: not a layer on top of anything, but a parallel variant of the entire stack (Easy Mode included) for a different cloud environment.

**v2 — core Hard Mode:**
- Hybrid AD DS-joined session hosts (traditional Kerberos, GPO-based FSLogix config instead of registry/CSE)
- Entra Domain Services as a middle-ground identity option
- VNet peering to an existing hub/on-prem network (VPN Gateway or ExpressRoute) — the actual groundwork the hybrid AD DS and Private Link items above both quietly depend on; called out as its own unit of work rather than assumed
- AVD Private Link + custom DNS (Infoblox integration, given your existing work there)
- Custom golden image pipeline (Azure Compute Gallery + versioning)
- Intune management (compliance policies, configuration profiles, security baselines, Win32 app deployment) — including an Intune Settings Catalog profile as a more "correct" modern-management replacement for the Custom Script Extension-based FSLogix registry push in Section 6
- Conditional Access policy build-out as part of the deployment itself
- Optional integration with a separate Azure Current State Documentation tool via a readiness-report input (see Section 16)

**v3 — further out:**
- Azure Bastion for direct admin RDP/troubleshooting access to session hosts — doesn't require or reintroduce a public IP (Section 2/8 stays intact), just an optional operational convenience layered on top once the core architecture is in place
- App Attach instead of/alongside full desktop app group — an application-delivery alternative, not a core connectivity/identity decision, so it fits better as a layered addition than a v2 architecture item
- GPU-enabled session hosts for graphics workloads — a workload-specific variant rather than a foundational architecture change; slots in once the core patterns above are established
- Multi-region host pools / DR — scaling the same core pattern geographically rather than changing its architecture; makes more sense once the single-region v2 patterns (Private Link, hybrid identity) are already proven out

**v4 — even further out:**
- Azure Local / Azure Hybrid (Azure Stack HCI) — running AVD session host infrastructure on-premises while still using the Azure control plane. A fundamentally different infrastructure model rather than a networking, workload, or geographic variant, so it gets its own tier rather than folding into v2 or v3

**v5 — separate cloud variant:**
- A complete Azure Government (GovCloud/GCC High) variant of Lab Kit — not a configuration flag on the Commercial build, and not "on top of" v2–v4 the way those layer on each other. GovCloud has its own endpoint set (`*.azure.us`/`usgovcloudapi.net`), different marketplace image availability, different supported regions, and its own compliance overlay (FedRAMP High baseline, sometimes ITAR/DoD IL depending on the specific Gov environment). Realistically this means a parallel Easy Mode-equivalent build targeting GovCloud endpoints from the ground up, not a Hard Mode add-on to the Commercial stack

Each v2 item could become its own module added to the same `/bicep/modules` folder without disrupting the Easy Mode path — the tiered structure (v2 through v4) is designed so Hard Mode is additive, not a rewrite. v5 is the exception: it's a parallel variant, not an additive layer, so it would realistically start from its own copy of the Easy Mode foundation rather than building on the Commercial v2–v4 work.

---

## 14. Leak Prevention

Since this repo goes public on July 29, treat secrets/leak prevention as a standing practice from the first commit, not a one-time scan the week before release.

**Never commit real values:**
- `avdlab.bicepparam` and `orchestrator.config.json` in the tracked repo hold placeholder values only (e.g. `<YOUR_SUBSCRIPTION_ID>`, `<YOUR_TENANT_ID>`, `<DEMO_GROUP_OBJECT_ID>`)
- Real values for your own test subscription live in a local, gitignored override file (e.g. `avdlab.local.bicepparam`, `orchestrator.local.config.json`) that's never staged
- Add both patterns to `.gitignore` from the very first commit, before there's anything to leak
- No hardcoded local admin passwords anywhere — already covered in Section 5 (random runtime generation, discarded after provisioning); this stays a hard rule, not a suggestion

**Automated scanning, not just a one-time check:**
- Add a `gitleaks` (or similar) pre-commit hook locally, so a real ID or key never makes it into a commit in the first place — this is the actual leak-prevention control; the pre-release scan is a backstop, not the primary defense
- Add `gitleaks` as its own CI job in `.github/workflows/ci.yml` alongside bicep-lint and Pester, so it's enforced even on a commit where the local hook was skipped or bypassed
- Once the repo goes public, GitHub's secret scanning runs automatically at no cost for public repos — enable push protection at the same time you flip visibility (Settings → Code security), so it's active from minute one of being public rather than something turned on later

**If something real ever does get committed before you catch it:**
- Deleting the value in a later commit does **not** remove it from history — anyone can still find it in an older commit once the repo is public
- Rotate/invalidate the actual credential or ID immediately — assume it's compromised the moment it's committed, regardless of whether it's ever pushed to a public remote
- Scrub the offending commit from history (`git filter-repo` or BFG Repo-Cleaner) **before** flipping the repo to public — this is the mandatory version of the Jul 27 secrets/history scan already in the release plan, not an optional nice-to-have if a real value was ever committed

**For the long run:** since Section 13's Hard Mode roadmap anticipates this repo growing and possibly taking outside contributions, put a short "Secrets & Leak Prevention" note in the README/CONTRIBUTING guidance so it's a documented norm for future PRs, not just something you personally remember to do.

---

## 15. Path to v1 Release — 3-Week Plan (Jul 8 → Jul 29)

Target: v1 (Easy Mode) tagged, released on GitHub, and announced on LinkedIn by **July 29**. This is a code-release milestone, separate from the live September WEUC demo — the goal here is a working, tested, publicly-forkable repo, not the presentation itself.

**Week 1 (Jul 8–14) — Repo + core Bicep modules**
- Jul 8–9: **Private** GitHub repo (flip to public on release day, not before — see below), MIT license, folder structure (Section 4). Note: classic branch protection/rulesets requiring CI-before-merge only apply to private repos on Pro/Team/Enterprise, not Free — as solo committer, self-gate by checking CI status before merging rather than relying on an enforced rule
- Jul 9: Stand up the CI workflow skeleton immediately (even empty/passing) so every commit going forward is checked — GitHub Actions runs the same on private repos, well within Free tier's monthly minutes for a workflow this size
- Jul 9–10: Prototype Azure AD Kerberos/FSLogix (Section 6) in isolation — highest risk item, do it first
- Jul 10: Build `Initialize-AvdLabPrerequisites.ps1` (Section 19) and run it against your own test subscription/tenant first — cheapest way to surface quota, licensing, or Security Defaults gaps before they cost you time later in the build
- Jul 11–14: Build `network.bicep`, `storage.bicep`, `hostpool.bicep`, `workspace.bicep`, `appgroup.bicep`; confirm each deploys cleanly with `what-if`

*Checkpoint:* core infra modules deploy cleanly in a test subscription.

**Week 2 (Jul 15–21) — Session hosts, orchestrator, real QA**
- Jul 15–16: `sessionhosts.bicep` (verify current marketplace image SKU before building, per Section 12 — don't assume the Section 7 example value) + `monitoring.bicep` (Log Analytics with scoped categories/retention, plus the budget + action group alert) + `scalingplan.bicep`
- Jul 17–18: PowerShell orchestrator — `Deploy-AvdLab.ps1`, `Remove-AvdLab.ps1`, `Set-AvdLabFSLogixAuth.ps1`, `Add-AvdLabAssignments.ps1`, `Test-AvdLabDeployment.ps1`, `New-AvdLabReport.ps1`
- Jul 19–20: Pester tests (parameter validation, naming convention checks); wire real checks into CI (bicep build per module + Pester on every push/PR)
- Jul 21: First full end-to-end integration deploy in test subscription — just confirming completion, not polish

*Checkpoint:* full deploy + teardown completes end-to-end at least once; CI green on all commits.

**Week 3 (Jul 22–28) — Dry runs, hardening, release prep**
- Jul 22–23: Fix whatever broke Jul 21; re-run until clean
- Jul 24: Dry run #1 — deploy from a clean subscription, timed, teardown, confirm nothing orphaned
- Jul 25: Dry run #2 — repeat to confirm repeatability, not just a one-off success
- Jul 26: README pass — follow the structure outline in Section 4 (prereqs/setup steps, deploying, tearing down, troubleshooting, Easy Mode/Hard Mode framing)
- Jul 27: Repo polish — LICENSE, `CONTRIBUTING.md`, topics/tags, cleanup of debug/TODO cruft, secrets/history scan (e.g. `gitleaks`) before the repo goes public
- Jul 28: Tag `v1.0.0`, draft GitHub Release notes, draft LinkedIn post; buffer day for slippage in *this* 3-week build — separate from the drift-check buffer for the September gap, see Section 18

**Jul 29:** Flip repo visibility to public (Settings → Danger Zone → Change visibility, or `gh repo edit --visibility public`), publish GitHub Release, post LinkedIn announcement. Not the finish line — see Section 18 for what happens between here and September.

**Automated QA approach:** GitHub Actions CI (`.github/workflows/ci.yml`) runs on every push/PR — `az bicep build` against each module (catches syntax/semantic errors), Pester tests (parameter/naming validation), and a `gitleaks` scan (Section 14) so secrets are caught at commit time, not discovered during the pre-release scan. Paired with self-gating on CI status before merging (see the branch protection note above), this is what makes "automated QA" an actual gate rather than a manual step someone can skip. An optional stretch addition, if time allows after the core CI is solid, is a `what-if`-based validation job against a real subscription using GitHub OIDC federated credentials (no stored secrets) — noted as commented-out in the starter workflow, not required for the 7/29 date.

---

## 16. Companion Tooling — Azure Current State Documentation (Separate Project)

A related but separate tool — likely a v2 evolution of the existing AVD Current State Collector — is planned to inventory everything across all subscriptions a user has access to and score AVD readiness against Lab Kit's prerequisites (Easy Mode now, Hard Mode eventually).

**Decision: keep it a separate repo/project, not a module inside AVD Lab Kit.**

- **Different responsibility, different audience.** Lab Kit deploys one specific, opinionated lab pattern. A current-state/readiness tool is a general-purpose pre-sales/assessment asset, useful for any AVD engagement — merging them narrows the assessment tool's usefulness and expands Lab Kit's Easy Mode scope (Section 0) in the wrong direction.
- **Different blast radius.** Tenant-wide discovery (Resource Graph across management groups, Graph API tenant queries) is a much bigger surface than a single-lab deployment tool needs, and doesn't belong inside something meant to be small and forkable in one sitting.
- **Reusability.** This is squarely useful for any customer engagement, independent of whether someone's using it to prep for this specific lab.

**What Lab Kit does instead: consume, don't generate.**

- The current-state tool emits a small, versioned JSON contract — e.g. `avd-readiness-report.json` — covering subscriptions/RBAC found, existing AD DS presence, licensing detected, region support for Azure AD Kerberos, network topology summary
- `Connect-AvdLabContext` (Section 4) gets an optional `-ReadinessReport <path>` parameter. If supplied, it cross-checks Lab Kit's own prerequisites (Section 3) against the report and fails fast on gaps — e.g. "report shows no Win11 multi-session licensing in this tenant" — instead of discovering that mid-deployment
- Lab Kit's own code never does tenant-wide discovery itself; it only ever reads a report another tool produced

**Timing:** this integration point, and the current-state tool itself, are **not** part of the 7/29 Lab Kit release. Both are their own project on their own timeline — captured here (and cross-referenced in Section 13's Hard Mode roadmap) so the idea has a home without threatening the current deadline.

---

## 17. Logging, As-Built Documentation & Evidence Capture

Unlike Section 16's companion tool, this lives *inside* Lab Kit — it's about documenting what Lab Kit itself just built, not tenant-wide discovery. Keep that distinction clean: this function never looks outside its own deployment, the companion tool never looks inside one.

**One underlying capture, two output modes.** `New-AvdLabReport.ps1` reads the structured deployment log `Write-Log` already produces (Section 5) plus the outputs captured from each Bicep module deployment (resource IDs, host pool URL, workspace name, session host names, storage account/share, scaling plan schedule), and renders one of two things depending on how it's invoked:

- **`-Mode AsBuilt`** — run automatically by the orchestrator on successful completion. A clean Markdown (plus JSON) summary of what actually got deployed: resource names/IDs, host pool/workspace connection info, FSLogix share path, scaling plan schedule, deployment timestamp and duration. This is the real "here's what's running" reference document, not scrollback that vanishes when the terminal closes.
- **`-Mode Evidence`** — run automatically by the orchestrator's catch block on any failure, or callable manually anytime for troubleshooting. The full structured transcript, the captured Bicep deployment operation details for whichever step failed (`Get-AzResourceGroupDeploymentOperation`), and resource state at the point of failure, bundled into a single timestamped folder — what actually happened, and exactly where it broke.

**Why one function instead of two:** both modes read the same underlying log/output data — the only difference is what gets surfaced and how it's framed. One function with a mode switch keeps the deliverable list from growing needlessly and keeps the log format itself as the single source of truth for both stories.

**Callable standalone, not just orchestrator-triggered:** `New-AvdLabReport.ps1 -Mode Evidence -ResourceGroupName rg-avdlab-weuc` should work against an already-deployed (or partially-deployed) environment at any time — useful for troubleshooting something that broke well after the fact, not only in the moment of failure.

**Relationship to Section 16:** this stays entirely inside Lab Kit and only ever documents Lab Kit's own deployment — no tenant-wide discovery, no cross-subscription awareness, no overlap with the separate Azure Current State Documentation tool. That tool answers "is this environment ready for Lab Kit"; this function answers "what did Lab Kit just build, and if it didn't work, why."

**Relationship to Azure Monitor/AVD Insights (Section 2/4):** these are two different logging layers serving different purposes, not redundant. `New-AvdLabReport.ps1` documents the *deployment process itself* — what got built and whether it worked — and exists whether or not the environment stays running. Azure Monitor/AVD Insights documents the *deployed environment's ongoing behavior* — session host health, connection performance, agent status — for as long as it's up. One's a build record, the other's operational telemetry.

---

## 18. Post-Release Window (Jul 29 → September) — Drift-Check & Continued Improvement

v1.0.0 shipping on July 29 is a release milestone, not a finish line. Development continues through the actual September WEUC presentation — this window has three distinct jobs, kept separate rather than blurred into one vague "keep working on it":

**1. Drift re-validation — do this close to the actual presentation date, not right after 7/29.** Once the September date is locked, schedule a fresh end-to-end dry run in the week beforehand. Don't rely on the July validation holding six-plus weeks later — specifically re-check:
- Marketplace image SKU name (Section 12 already flags `win11-23h2-avd` as likely stale by build time — confirm the current SKU rather than assuming July's value still resolves)
- Az PowerShell module versions and the Azure AD Kerberos cmdlets (Section 6) — this surface has shifted before and could again
- Quota, resource provider registration, and Azure Policy pre-flight checks (Section 3) — re-run against whatever subscription actually gets used live, since it may not be the same one used for the July dry runs

**2. v1.x patch work** — smaller items from the pre-release review, shipped incrementally rather than having blocked 7/29 (cost guardrail alert, Log Analytics scoping, `CONTRIBUTING.md`, and the marketplace image SKU check moved into v1.0 scope directly — see Sections 2, 7, 11, 12):
- Standard resource tagging across modules
- Negative-path tests for the Section 3 pre-flight checks
- Swapping the custom `-Validate` switch for native `-WhatIf`/`-Confirm` (`SupportsShouldProcess`)

**AlertAndDelete cost guardrail mode — Automation Runbook mechanism (design only, not built for 7/29):**
- `costGuardrailMode` (Section 7) selects `AlertOnly` (v1.0 default) or `AlertAndDelete`. When `AlertAndDelete` is chosen, a new conditional module — `/bicep/modules/costguardrail.bicep` — deploys an Automation Account with a system-assigned managed identity, a Contributor role assignment scoped to just the resource group (nothing broader), and a runbook
- The runbook itself is a small, self-contained script — `Connect-AzAccount -Identity` followed by `Remove-AzResourceGroup -Force` — not a call into the local `Remove-AvdLab.ps1`, since Automation Runbooks execute in Azure's own sandbox with no access to repo files on disk. Source of truth lives at `/scripts/runbooks/Invoke-AvdLabCostTeardown.ps1` in the repo and gets published into the runbook resource via Bicep
- A second, much higher-threshold budget triggers that runbook directly through its action group — Action Groups can invoke an Automation Runbook natively, no Logic App or webhook glue needed
- Azure cost/usage data has 8–24+ hour reporting latency, so this can never fire mid-demo on the same day. The gap between the Tier 1 alert threshold and this Tier 2 delete threshold is what gives days, not hours, of manual-intervention room before it engages
- Deferred to v1.x specifically because *testing* it reliably — confirming the runbook actually fires and cleans up on a real threshold crossing — means either faking cost data or genuinely leaving something running for days; that test burden doesn't shrink just because the mechanism is lighter than a Logic App

**3. Decide the Hard Mode branching/versioning strategy.** This is the right window to settle where v2+ work actually lives (separate branch, later tagged release, or a parallel folder) — before any Hard Mode coding starts, not decided under demo-week pressure.

None of this changes the 7/29 date or the Section 1 scope — v1.0.0 ships with exactly what's in this spec, nothing added or held back. This section just gives the August gap a real job instead of leaving it as dead time between two dates.

---

## 19. Greenfield Setup Runbook — `Initialize-AvdLabPrerequisites.ps1`

**Purpose:** a standalone, run-once script that takes a brand-new greenfield subscription + Entra tenant from zero to "ready for Lab Kit." Distinct from `Connect-AvdLabContext`'s pre-flight checks (Section 3/4) — different verb, different moment.

**Relationship to `Connect-AvdLabContext`:** `Connect-AvdLabContext` always runs at the start of every `Deploy-AvdLab.ps1` invocation and only ever checks/reports/fails fast — it never remediates anything. `Initialize-AvdLabPrerequisites.ps1` is optional, run once by choice before ever attempting a deployment, and actually takes action where it safely can. "Setup once, verify every time" — not two copies of the same check.

**Relationship to Section 16's companion tool:** stays entirely inside Lab Kit and only ever touches the one subscription/tenant about to be deployed into — no tenant-wide, cross-subscription discovery. Same boundary Section 16/17 already drew, held here too.

**Auto-remediates (idempotent, safe to run repeatedly):**
- Registers the four required resource providers (`Microsoft.DesktopVirtualization`, `Microsoft.Compute`, `Microsoft.Network`, `Microsoft.Storage`) — `Register-AzResourceProvider` is a no-op if already registered

**Reports only — can't safely act, so it states the gap clearly instead of pretending to fix it:**
- **vCPU quota** — a fresh subscription (especially Free Trial or new Pay-As-You-Go) can be quota-constrained on day one with nothing else running, unlike the brownfield case where the risk comes from something else already consuming it. Quota increase requests aren't instant, so this needs surfacing early, not discovered on presentation morning
- **Windows 11 Enterprise multi-session licensing** — a genuinely fresh tenant likely has zero M365/Windows licensing by default; this is a procurement/trial-activation decision, not something a script can provision
- **Entra ID Security Defaults** — on by default for new tenants, enforcing MFA for everyone. **This is the single most likely reason a greenfield run fails, and it is a blocker rather than a warning** (Section 6/12): with Security Defaults on, the storage account app cannot be excluded from MFA, so FSLogix profiles cannot load. There is no per-app exclusion to configure — the tenant owner must consciously disable Security Defaults and replace it with Conditional Access policies (Entra ID P1). The script reports this as **action-needed**, loudly, and cannot fix it: turning off a tenant's baseline security is not a decision a lab setup script gets to make on someone's behalf. Register the demo account's MFA before presentation day regardless
- **MDM auto-enrollment scope** — reports current state; a fresh tenant usually defaults to no scope configured, so this typically comes back clean, but the script checks rather than assumes
- **Global Admin / subscription RBAC** — confirms the identity running the script actually holds Global Admin (or equivalent) in the tenant and Contributor + User Access Administrator on the target subscription, rather than assuming access follows automatically from having created the tenant

**Output:** a short readiness report (console, optionally saved to file) — a plain pass/fail/action-needed list scoped to exactly Section 3's prerequisites, not the broader `avd-readiness-report.json` contract from Section 16 (that's the separate tool's format, covering far more than one target environment).

**Timing:** contained enough (a handful of read checks + a few idempotent registration calls) to fold into v1.0 rather than defer — worth building early in Week 1, since it's also the fastest way to get your own dev/test subscription actually ready before the rest of the build starts.
