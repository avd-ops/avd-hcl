# CLAUDE.md — AVD Lab Kit

Read automatically by Claude Code at the start of every session in this repo. It holds the build spec: architecture decisions, module boundaries, and the scope rules that keep this project small enough to be useful.

## How to work in this repo

- Follow the module boundaries below. Don't invent new top-level structure without saying so.
- **Easy Mode is the whole scope.** Anything from the Hard Mode roadmap goes in the roadmap, not into a change here. See [Scope discipline](#scope-discipline).
- There is a **second, independent axis** under discussion: lifecycle management (running several labs, stopping them, reaping expired ones). It is *not* Hard Mode — it is a different job, not harder architecture. `docs/lab-management.md` specs it. **Nothing in that document is built**, and it is not licence to add lifecycle features here until it is agreed.
- **Verify claims about Azure against current docs rather than trusting this file.** API versions, image SKUs, preview/GA status and cmdlet surfaces all move. Where this document states a fact about Azure, treat it as "true when written," and re-check it before a deployment anyone is depending on.
- The leak-prevention rules are non-negotiable: no real subscription/tenant/object IDs, no real email addresses, no hardcoded secrets in tracked files. Placeholders only. See `CONTRIBUTING.md`.
- Headings here are named, not numbered, and code comments deliberately do not cross-reference them. A comment should explain itself where it sits; a pointer into a spec file only rots.
- If a decision here looks wrong once you're actually building, say so rather than silently changing course.

---

## Easy Mode / Hard Mode

This is a two-tier project, and the split is load-bearing.

**Easy Mode (this repo)** — the simplest deployable AVD lab that is still a legitimate, real-world-shaped pattern. Entra ID join only, no on-prem dependency, small autoscaled pool, one resource group, teardown in one command. Built to be understood in one sitting and forked by anyone without needing a domain controller or directory sync running first.

**Hard Mode (roadmap, not built here)** — the harder "how it actually looks at a customer" scenarios, layered onto the same module foundation. Captured in [Hard Mode roadmap](#hard-mode-roadmap) so the ideas have a home without pulling scope into this build.

Keeping these explicitly separate is what stops Easy Mode accreting scope from "well, while we're in here…"

**Easy Mode's brownfield story is non-interference, not emptiness.** It works in a subscription that already has other workloads: isolation comes from a dedicated resource group, so it touches nothing outside it. Hard Mode's brownfield story is a different and harder problem — *integration*: peering into an existing corporate VNet, joining an existing forest, using existing DNS. That, rather than "simple vs. complex," is the real distinction between the tiers.

---

## Scope

**In scope:**
- Entra ID-joined session hosts (no AD DS, no Entra Domain Services)
- Pooled host pool, Windows 11 Enterprise multi-session
- 2–3 session hosts with an autoscale scaling plan
- FSLogix profile containers on Azure Files via Microsoft Entra Kerberos
- Log Analytics workspace + AVD Insights (diagnostic settings, data collection rule and agent on session hosts)
- Desktop app group + workspace, single VNet
- Cost guardrail: budget + action group email alert
- Full teardown

**Cloud environment:** Azure Commercial only. Azure Government is not a configuration option — it is a complete separate variant with its own endpoints, image availability and compliance overlay.

**Explicitly out of scope — these are Hard Mode:**
- Hybrid identity / AD DS
- VNet peering, on-prem connectivity (VPN Gateway, ExpressRoute, hub-and-spoke)
- Intune management
- Multi-region or DR
- Azure Local / Azure Stack HCI
- Azure Government / GCC High
- Private Link, custom DNS, Conditional Access build-out
- Custom golden images, App Attach, GPU workloads

Saying this out loud to an audience is a feature, not a caveat — "here's the easy path, and here's what gets harder" is a stronger structure than pretending this is the whole story.

### Scope discipline

If a change requires a domain controller, a VNet peering, a Private Link endpoint, a custom image, Intune, a GPU, a second region, or Azure Government endpoints — it is Hard Mode. That is not a rejection of the idea; it is what keeps Easy Mode easy.

---

## Key architecture decisions

| Decision | Choice | Why |
|---|---|---|
| IaC approach | Bicep modules, one per resource type | Native idempotency, `what-if` support, reusable artifact for anyone reading it |
| Orchestration | Thin PowerShell wrapper, sequential deployments | Preserves phase-by-phase narration a monolithic template can't give you, and localises failures to a named step |
| Identity | Entra ID join only | Simplest story, no domain controller to explain or build — this *is* the Easy Mode line in the sand. Genuinely Intune-free by design: MDM enrollment is a separate tenant-level setting, not a dependency of Entra join |
| Host pool type | Pooled, multi-session | Matches "small pool with autoscale" |
| Session host OS | Win11 Enterprise multi-session, marketplace image | Fastest path; custom images are Hard Mode |
| Profile management | FSLogix on Azure Files | Standard for pooled — and the one genuinely non-trivial config item, see [Entra Kerberos](#fslogix--entra-kerberos-the-hard-part) |
| Monitoring | Log Analytics + AVD Insights | Standard expectation even for a lab; self-contained, no Intune or AD dependency |
| Scaling plan | Ramp-up/peak/ramp-down/off-peak schedule | Visual, easy to narrate, and the clearest demonstration that cost follows usage |
| Networking | Single VNet/subnet + NSG + NAT gateway, no public IP on any session host | AVD's reverse-connect transport means there is never an inbound connection to a session host. **Outbound is not free, though:** since default outbound access retired on 2026-03-31, new VNets default to private subnets and Azure grants no implicit egress. Without an explicit path the agent can't register and the pool comes up empty. `defaultOutboundAccess` is set explicitly rather than inherited, so behaviour doesn't change with the apiVersion string |
| App group | Desktop app group | Simplest; RemoteApp is an optional extension |
| Resource scoping | Everything in one resource group | Teardown is one call |
| Subscription assumption | Brownfield-safe via dedicated RG isolation | No VNet peering or naming assumptions that would require an empty subscription |
| Cost guardrail | Budget + action group email alert, scoped to the RG | Alerts on runaway spend without auto-deleting a possibly-live environment. `costGuardrailMode` also names an `AlertAndDelete` design, which is **not built** — the orchestrator rejects it rather than letting it deploy as a silent no-op |

---

## Solution structure

```
/bicep
  /modules
    network.bicep          # VNet, subnet, NSG, NAT gateway — no public IP, no inbound rules
    storage.bicep          # storage account + FSLogix share, incl. directoryServiceOptions: 'AADKERB'
    hostpool.bicep         # host pool + @secure() registration token via listRegistrationTokens()
    appgroup.bicep         # desktop app group; deploys BEFORE workspace
    workspace.bicep        # workspace; takes the app group ID and publishes it
    sessionhosts.bicep     # N VMs, no public IP, Entra join, AVD agent, FSLogix/Kerberos client config
    monitoring.bicep       # Log Analytics, AVD diagnostics, DCR + agent, budget + action group
    scalingplan.bicep      # weekday autoscale schedule
  /parameters
    avdlab.bicepparam      # single source of truth for Bicep parameters (`using none`)
/scripts
  Deploy-AvdLab.ps1                 # orchestrator — calls modules in sequence, narrates progress
  Initialize-AvdLabPrerequisites.ps1 # one-off readiness check; the only script that remediates
  Remove-AvdLab.ps1                 # teardown + orphan check
  Set-AvdLabFSLogixAuth.ps1         # Entra app-registration fixups — Graph, not ARM
  Add-AvdLabAssignments.ps1         # the three role assignments the lab needs
  Test-AvdLabDeployment.ps1         # smoke test for the silent failures
  New-AvdLabReport.ps1              # as-built on success, evidence bundle on failure
/tests
  AvdLab.Tests.ps1                  # Pester — leak prevention, parameter guards, repo shape
/docs
  bootstrap.md                      # manual subscription/tenant setup runbook
orchestrator.config.json            # PowerShell-layer settings that aren't Bicep parameters
```

### Orchestrator sequence

1. Connect Az + Graph, validate subscription/tenant context, fail fast if wrong; run pre-flight checks (providers, quota, inherited Azure Policy)
2. `network.bicep`
3. `storage.bicep`
4. `Set-AvdLabFSLogixAuth.ps1` — the Graph work ARM can't express
5. `hostpool.bicep` — capture the registration token (a `@secure()` output; `registrationInfo.token` is write-only and a GET never returns it)
6. `appgroup.bicep`, **then** `workspace.bicep` — this order matters. The link is stored on the *workspace* as `applicationGroupReferences`, so building the app group first links both sides in one pass. The reverse order needs the workspace deployed twice
7. `sessionhosts.bicep`, passing the registration token and a runtime-generated admin password
8. `monitoring.bicep` — needs the session hosts to exist for the agent and DCR association
9. `scalingplan.bicep`
10. `Add-AvdLabAssignments.ps1`
11. `Test-AvdLabDeployment.ps1`
12. `New-AvdLabReport.ps1 -Mode AsBuilt`; the catch block runs `-Mode Evidence` instead

Each step is a discrete `New-AzResourceGroupDeployment` rather than one `main.bicep`. That is what preserves "watch it build, phase by phase" while still getting Bicep's idempotency and diffability at each phase.

---

## Idempotency and error handling

- **Bicep handles resource-level idempotency natively.** Re-running converges rather than erroring on "already exists," which removes essentially all the `Get-Az*`-before-`New-Az*` boilerplate a pure-PowerShell version would need.
- The orchestrator wraps every deployment in try/catch, logs through a central `Write-Log` (console line for the room, structured JSON Lines record for the report), and checks each deployment result before proceeding. If a phase fails, the next one does not run.
- `-Validate` runs every module through `what-if` and changes nothing.
- The session host local admin password is generated at runtime with a cryptographic RNG, never written anywhere, and discarded when the process exits. Entra join removes any long-term need for it. **A `@secure()` parameter with a default value is the same mistake wearing a hat** — the Pester suite fails the build if it finds one.
- Child scripts stay standalone-runnable and print plain console output; the orchestrator is what turns that into a structured record. That is deliberate, and it is why there is no shared logging module to install.

---

## FSLogix + Entra Kerberos: the hard part

With no AD DS and no Entra Domain Services, FSLogix profile access to Azure Files depends on **Microsoft Entra Kerberos**, not traditional Kerberos. This is the part of the build most likely to fail, and most likely to fail *silently*.

Entra-only (cloud-only) identity support for Azure Files SMB reached **GA on 2026-05-19**. What GA did not change is any of the configuration below.

**Bicep-native (`storage.bicep`)** — the storage account, SMB settings, share, and the Kerberos toggle itself:

```bicep
properties: {
  azureFilesIdentityBasedAuthentication: {
    directoryServiceOptions: 'AADKERB'
  }
}
```

No `activeDirectoryProperties` block is needed for cloud-only identities — `domainName`/`domainGuid` are only required for hybrid identities configuring ACLs through File Explorer. Keeping this declarative means a re-run converges instead of drifting. `Set-AzStorageAccount -EnableAzureActiveDirectoryKerberosForFile $true` remains a valid imperative fallback.

**Not Bicep-native (`Set-AvdLabFSLogixAuth.ps1`)** — enabling the toggle makes Azure mint an Entra app registration for the storage account. Three things must then be done *to that app registration*. All are Microsoft Graph, all need Global Admin, none are ARM resources:

1. **Grant admin consent** to the new service principal.
2. **Ensure no MFA requirement applies to it.** Kerberos tickets are acquired silently at logon; there is no UI to satisfy a step-up prompt. Without this, mounting the share fails with `System error 1327: Account restrictions are preventing this user from signing in`.
   > **Security Defaults is a hard blocker, not a hurdle.** Excluding an app from an MFA requirement is a Conditional Access operation; Conditional Access requires Entra ID P1; and Security Defaults is all-or-nothing with no per-app exclusion. A tenant running Security Defaults **cannot host a working Entra Kerberos FSLogix share.** The remedy is tenant-level and deliberate. The script detects this, explains it, and stops — it will not weaken a tenant's security posture to make a lab deploy. Security Defaults is on by default for new tenants, so a greenfield path hits this every time.
3. **Add the `kdc_enable_cloud_group_sids` app manifest tag.** *Mandatory for cloud-only identities.* Without it Entra omits cloud-only group SIDs from the ticket and share permissions granted to an Entra group never resolve. This is the step most likely to fail quietly, because everything looks correct right up until a profile fails to load. Note the Graph `tags` collection is **replace-in-full** — read and merge, never assign, or you drop whatever Azure already stamped on the app.

**Share-level authorization (`Add-AvdLabAssignments.ps1`)** — for cloud-only identities there are **no NTFS ACLs in the picture at all**. Share access is governed entirely by Azure RBAC: the demo group needs `Storage File Data SMB Share Contributor` on the storage account, or profiles fail to load with all three Graph steps done correctly.

**Client-side (`sessionhosts.bicep`, via Custom Script Extension)** — two registry values on every session host, plus FSLogix's own `Enabled`/`VHDLocations`:

- `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters\CloudKerberosTicketRetrievalEnabled = 1`
- `HKLM\Software\Policies\Microsoft\AzureADAccount\LoadCredKeyFromProfile = 1`

Two Windows services must also be running — verify, don't assume, since a hardening baseline may have disabled them:

- `WinHttpAutoProxySvc` — carries the KDC Proxy requests ticket retrieval depends on. Disabling WPAD itself via registry is fine; the *service* must run.
- `iphlpsvc`

FSLogix ships pre-installed on the Windows Enterprise multi-session marketplace images — it needs configuring, not installing.

**Other constraints:**
- Confirm your target region supports Entra Kerberos for Azure Files. The cloud-only path is Azure Commercial only, consistent with the scope above.
- **RC4 → AES-SHA1 Kerberos hardening shipped in the April 2026 Windows update.** Shares not on AES-SHA1 have access issues. Build on AES-SHA1 from the start.
- Have a fallback: `-SkipFSLogix` lets the rest of the lab (host pool, autoscale, app group) run with local profiles if Kerberos won't cooperate.

---

## Parameters

`bicep/parameters/avdlab.bicepparam` drives everything Bicep needs. It uses **`using none`**, because a `.bicepparam` binds to exactly one template and may only assign parameters that template declares — one file spanning eight modules is rejected with `BCP259`. `using none` decouples it, compiles standalone to a `deploymentParameters` document, and the orchestrator passes each module only the parameters that module declares.

What that trades away is compile-time type checking, so `tests/AvdLab.Tests.ps1` carries the burden instead: the file compiles, every assigned name is declared by some module, no ambiguous name is assigned, no runtime-injected value is pinned, and every module's required parameters are satisfied.

**Name collisions are the non-obvious hazard of a flat file.** Parameter names are module-scoped: `friendlyName` means four different things across the AVD modules, so assigning it once would splat one string into all of them. Only lab-wide values (`location`, `tags`), names that mean the same thing everywhere (`hostPoolName`, `appGroupName`, `workspaceName`), or unambiguous ones belong there. The Pester suite enforces this, and adding a name to its shared-parameters list is a claim that you checked.

`orchestrator.config.json` holds the settings that are purely for the PowerShell layer: the demo group object ID, narration toggles, and the scaling plan schedule times — editable without touching Bicep.

**Diagnostic category scoping:** enable `Checkpoint`, `Error`, `Management`, `Connection`, `HostRegistration` and `AgentHealthStatus` — what AVD Insights actually needs. Leave `NetworkData` and `ConnectionGraphicsData` off; they are higher volume and answer production performance questions a short-lived lab doesn't ask. Realistically the cost exposure is *how long the environment stays running*, which is what the budget alert is for.

**Naming convention:** `<resourceType>-avdlab-<qualifier>` across both layers.

---

## Reporting

`New-AvdLabReport.ps1` reads the structured transcript plus the captured module outputs and renders one of two things:

- **`-Mode AsBuilt`** — run automatically on success. What actually got deployed: names, resource IDs, connection info, FSLogix share path, autoscale schedule, timings. A reference document rather than scrollback that vanishes when the terminal closes.
- **`-Mode Evidence`** — run automatically by the catch block, or by hand at any time. The full transcript, the failing deployment's operation detail (`Get-AzResourceGroupDeploymentOperation`), and resource state at the point of failure.

One function with a mode switch, because both read the same data and the log format should stay the single source of truth for both stories. Both run standalone against an already-deployed or partially-deployed environment.

**This never looks outside its own deployment.** No tenant-wide discovery, no cross-subscription awareness. It answers "what did this build, and if it didn't work, why."

**Relationship to Azure Monitor / AVD Insights:** two different layers, not redundant. This documents the *deployment process* and exists whether or not the environment is still running. AVD Insights documents the *deployed environment's ongoing behaviour*. One is a build record, the other is operational telemetry.

---

## Testing

- **Unit:** Pester — leak prevention, parameter-file guards, repo shape, script parse checks.
- **Lint/compile:** `bicep build` per module in CI, with **warnings treated as failures**. `bicep build` exits 0 on a warning, and warnings like `BCP245` mean a resource will not deploy at all.
- **Secret scanning:** `gitleaks` as a local pre-commit hook (the primary control) and a full-history CI job (the backstop).
- **Integration:** full deploy in a test subscription, timed, to confirm it fits the window you have.
- **Teardown verification:** confirm nothing is orphaned. The storage account's Entra app registration is the one that survives a resource group delete.

---

## Leak prevention

- Tracked `avdlab.bicepparam` and `orchestrator.config.json` hold placeholders only (`<YOUR_SUBSCRIPTION_ID>`, `<DEMO_GROUP_OBJECT_ID>`, `<YOUR_EMAIL>`).
- Real values live in gitignored local overrides: `avdlab.local.bicepparam`, `orchestrator.local.config.json`. The orchestrator prefers them automatically.
- Generated reports contain real IDs and are gitignored.
- No hardcoded passwords anywhere, ever.
- If a real value is ever committed: rotate it immediately — assume it is compromised the moment it is committed, whether or not it was pushed — then scrub it from history with `git filter-repo` or BFG. Deleting the line in a later commit does nothing.

See `CONTRIBUTING.md` for the contributor-facing version.

---

## Hard Mode roadmap

Parked here so Easy Mode stays Easy Mode. Tiered so Hard Mode is additive rather than a rewrite.

**v2 — core integration scenarios:**
- Hybrid AD DS-joined session hosts (traditional Kerberos, GPO-based FSLogix config)
- Entra Domain Services as a middle-ground identity option
- VNet peering to an existing hub/on-prem network (VPN Gateway or ExpressRoute) — the groundwork hybrid AD DS and Private Link both quietly depend on
- AVD Private Link + custom DNS
- Custom golden image pipeline (Azure Compute Gallery + versioning)
- Intune management — including a Settings Catalog profile as a more "correct" modern-management replacement for the CSE-based FSLogix registry push
- Conditional Access policy build-out as part of the deployment

**v3 — layered additions:**
- Azure Bastion for admin access to session hosts (needs no public IP; the network design stays intact)
- App Attach alongside or instead of a full desktop app group
- GPU-enabled session hosts
- Multi-region host pools / DR

**v4 — different infrastructure model:**
- Azure Local / Azure Stack HCI — AVD session hosts on-premises with the Azure control plane

**v5 — parallel cloud variant:**
- A complete Azure Government / GCC High variant. Not a config flag and not a layer on v2–v4: different endpoints, different marketplace availability, different supported regions, its own compliance overlay. Realistically a parallel Easy Mode-equivalent build rather than an add-on.

**Companion tooling (separate project, not part of this repo):** a current-state/readiness tool that inventories subscriptions and scores AVD readiness belongs in its own repo. Different responsibility, different audience, and a much larger blast radius — tenant-wide discovery does not belong inside something meant to be small and forkable. If it exists, Lab Kit should *consume* its output (a small versioned JSON report) and never do tenant-wide discovery itself.
