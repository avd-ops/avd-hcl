# Lab management — design spec

> **Status: proposed, not built.** This describes a second capability layered on the existing deployment tool. Nothing in this document exists yet.

## Why this is a new axis, not a new tier

Lab Kit already has one axis of variation: **Easy Mode vs. Hard Mode**, which is about *architectural complexity* — Entra join versus hybrid AD DS, one VNet versus a peered hub.

Management is a different axis: *lifecycle and operations*. You can want full lifecycle control over a dead-simple Easy Mode lab, and the two choices are independent. Filing this under "Hard Mode v2" would be a modelling mistake — it isn't harder architecture, it's a different job.

So the project now has two dimensions:

|                  | Easy Mode          | Hard Mode          |
| ---------------- | ------------------ | ------------------ |
| **Unmanaged**    | what exists today  | roadmap            |
| **Managed**      | this document      | later, if ever     |

Everything below assumes Easy Mode architecture. Management of Hard Mode labs is not in scope and may never be.

---

## What problem this solves

The current tool deploys a lab, demonstrates it, and destroys it. That is a complete story for a single scripted demo. It falls down the moment labs outlive a single sitting:

- **Nothing knows what exists.** Every question about the estate means querying Azure by hand.
- **Nothing reaps.** The budget alert emails you. An abandoned lab runs until somebody notices.
- **You cannot pause.** The only way to stop paying for an idle lab is to delete it, and the only way to get it back is a full redeploy.
- **Teardown erases the record.** What a lab was for, what it cost, and what was built go away with the resource group.
- **Only one lab can exist.** Resource names are fixed literals, and storage account names are globally unique, so a second concurrent lab cannot deploy at all.

Target: **a few concurrent labs**, operated by one person from a CLI. Not a per-attendee fleet, not self-service.

---

## Concepts

**Lab** — one resource group containing one complete AVD environment, identified by a short **lab name** (`demo`, `scratch`, `weuc`). The lab name is the only thing a user needs to supply to address a lab.

**Lab state** — where a lab is in its lifecycle. Derived from Azure, never stored as a claim that could go stale:

| State | Meaning | How it is detected |
| --- | --- | --- |
| `Running` | Session hosts allocated, accepting sessions | ≥1 host allocated and not draining |
| `Stopped` | Deallocated on purpose, still fully configured | All hosts deallocated, scaling plan disabled |
| `Expired` | Past its expiry tag, not yet reaped | `avdlab-expires` in the past |
| `Incomplete` | Deployment failed partway | RG exists, smoke test fails |
| `Absent` | No resource group | — |

`Stopped` is the state that matters commercially: compute stops billing, the storage account and its profiles survive, and restarting is seconds rather than a redeploy.

---

## Identity and naming

Every resource name gains a lab-name token, extending the existing `<resourceType>-avdlab-<qualifier>` convention:

```
rg-avdlab-<labName>          resource group
vnet-avdlab-<labName>        virtual network
hp-avdlab-<labName>          host pool
ws-avdlab-<labName>          workspace
dag-avdlab-<labName>         application group
log-avdlab-<labName>         Log Analytics workspace
sp-avdlab-<labName>          scaling plan
vm-<labName>-0..n            session hosts
```

Lab names are constrained to **3–9 characters, lowercase letters and digits**. That is not arbitrary, and an earlier draft of this document got it wrong by saying 3–12: the Windows computer name limit is 15 characters and session hosts are named `vm-<labName>-<n>`, with `sessionHostCount` allowing a two-digit index.

```
'vm-' (3) + labName (9) + '-' (1) + '49' (2) = 15
```

A 12-character lab name yields an 18-character computer name, which ARM rejects — at the session host phase, after the network, storage and host pool are already built. Bicep can constrain a parameter's length but not its character set, so `Deploy-AvdLab.ps1` validates the character set itself in pre-flight.

`labName` **defaults to `lab`**. That keeps the current single-lab workflow working unchanged: someone who forks this repo and runs `Deploy-AvdLab.ps1` without knowing management exists gets exactly what they get today, under a slightly different set of resource names. A mandatory lab name would break every existing fork on update to buy nothing.

### The storage account is the hard case

Storage account names are globally unique across all of Azure, 3–24 characters, lowercase alphanumeric with no hyphens. A predictable name like `stavdlab<labName>` would collide with every other person who forked this repo and picked the same lab name.

```bicep
var sanitised = toLower(replace(replace(labName, '-', ''), '_', ''))
var storageAccountName = 'st${take(sanitised, 9)}${uniqueString(resourceGroup().id)}'
```

`st` + 9 + `uniqueString`'s 13 = exactly 24 characters, the limit. `uniqueString(resourceGroup().id)` is deterministic — the same lab in the same resource group always resolves to the same name, so re-runs converge instead of creating a second account — while being globally distinct from anyone else's.

This replaces `storageAccountName` as a user-supplied parameter, which removes one of the two values that currently must be hand-edited before a first deployment, and removes the pre-flight availability check added for it.

---

## State model: tags are truth, the store is history

Two mechanisms, with a strict precedence rule: **where they disagree, Azure wins.** The store is never consulted to decide what exists.

### Tags — the live record

The resource group carries its own metadata. No sync, no drift, and teardown removes the record together with the thing it describes.

| Tag | Example | Purpose |
| --- | --- | --- |
| `avdlab-name` | `demo` | Identity; what every command addresses |
| `avdlab-owner` | `nick` | Who to ask before reaping |
| `avdlab-created` | `2026-09-19T14:02:00Z` | Age |
| `avdlab-expires` | `2026-09-26T14:02:00Z` | When the reaper may act |
| `avdlab-purpose` | `weuc rehearsal` | Why it exists — the thing you forget first |
| `avdlab-kit-version` | `1.0.0` | What built it, for debugging old labs |

Discovery is `Get-AzResourceGroup -Tag @{ 'avdlab-name' = ... }`, which is `Az.Resources` — already a dependency. Azure Resource Graph would be needed only to span subscriptions, and that is not in scope.

Tags are also how cost attribution works: a resource group tagged this way is directly queryable in Cost Management with no extra plumbing.

### The durable store — what tags cannot do

Tags die with the resource group. Everything you would want *after* a teardown needs somewhere else to live:

- the as-built report for each lab
- final cost, captured at teardown
- a lifecycle event log (created, stopped, reset, extended, destroyed)
- the parameters a lab was built from, so it can be recreated exactly

This lives in a storage account in a **separate control-plane resource group** (`rg-avdlab-control`), deliberately outside every lab so a teardown cannot touch it. One blob per lab, keyed by name and creation timestamp.

> **Deferred — see [Decisions](#decisions).** The store is not being built yet. Tags alone carry steps 1–4 of the build order, and because tags are the source of truth, adding the store later is purely additive and costs no rework. This section stays as the design to reach for if the need proves real.

---

## Verb surface

Existing scripts keep their names and gain `-LabName`. New verbs:

| Verb | Does |
| --- | --- |
| `Get-AvdLab` | List labs with state, age, expiry, cost to date. No argument lists all. |
| `Stop-AvdLab` | Deallocate to stop paying, preserving configuration and profiles. |
| `Start-AvdLab` | Reverse of Stop. |
| `Reset-AvdLab` | Return to a clean state without a full redeploy. |
| `Set-AvdLab` | Change expiry, owner, purpose. Mostly "extend by a week". |
| `Invoke-AvdLabReaper` | Find expired labs and act. Runs unattended. |

`Deploy-AvdLab` gains `-LabName`, `-ExpiresIn` (default 7 days) and `-Purpose`.

---

## Stop is not "deallocate the VMs"

This is the part most likely to be built wrong, because the naive version appears to work and then silently undoes itself overnight. **Three separate mechanisms will restart a stopped lab:**

1. **The scaling plan.** `rampUpMinimumHostsPct = 50` means at 08:00 the next weekday, half the hosts come back on. The plan does not know or care that you stopped them.
2. **`startVMOnConnect = true`** on the host pool. Any user who connects powers a host on. A "stopped" lab is one click from running.
3. **Drain mode.** Without it, hosts remain advertised as available targets even while deallocating.

So `Stop-AvdLab` must be a four-step operation, in this order:

1. Set `scalingPlanEnabled = false` on the host pool reference
2. Set every session host to drain mode (`allowNewSession = false`)
3. Notify and wait for active sessions, or force with `-Force`
4. Deallocate the VMs

`Start-AvdLab` reverses it: allocate, clear drain, re-enable the plan. The scaling plan is re-enabled **last**, so it cannot act on a half-started lab.

`Get-AvdLab` reports a lab as `Stopped` only when all four conditions hold. A lab with deallocated VMs but a live scaling plan is not stopped — it is *about* to be running — and reporting otherwise would be exactly the kind of confident-but-wrong status this project exists to avoid.

---

## Reset

"Clean" means no user state, without paying for a full redeploy. Two levels:

- **`-Profiles`** (default) — delete FSLogix profile containers from the share. Fast, seconds, and covers the common case of a demo user whose profile is now full of test junk.
- **`-Hosts`** — delete and redeploy the session hosts from the marketplace image. Slower, and the honest answer when a host has been manually tampered with mid-demo. Requires a fresh registration token, which `hostpool.bicep` already mints on every deployment.

Reset never touches the network, storage account, host pool, workspace or app group, so the workspace URL and all role assignments survive. Users do not need to re-subscribe.

---

## Expiry and reaping

The reaper is what makes this a management solution rather than a nicer deployment script — it is the only component that acts without being asked.

Default behaviour is deliberately conservative: at expiry, **stop** rather than destroy. Stopping reclaims nearly all the cost, is reversible, and cannot lose work. Destroying is opt-in per lab (`-OnExpiry Destroy`).

A lab is never reaped silently. Every action writes to the workflow run log and sends a notification through the action group `monitoring.bicep` already deploys.

### Where it runs: GitHub Actions

A scheduled workflow authenticating to Azure by OIDC. No stored secrets, no Azure infrastructure to host it, and the repo already carries a commented-out OIDC job to build on. This supersedes the unbuilt `AlertAndDelete` cost-guardrail mode — a budget threshold that deletes a resource group is a worse version of the same idea, firing on 8–24-hour-stale cost data rather than on an explicit expiry. **`AlertAndDelete` should be retired from the spec when this is built**, and `costGuardrailMode` reduced to the alert it actually is.

The workflow needs `permissions: id-token: write` for `azure/login@v2` to mint the token.

> **The federated credential subject must match exactly, and the Azure portal makes it easy to get wrong.**
>
> If you create the credential in the portal and fill in the *optional* GitHub owner/repository ID fields, the portal writes a subject of the form `repo:<org>@<org-id>/<repo>@<repo-id>:<entity>:<value>`. The token GitHub actually sends carries `repo:<org>/<repo>:<entity>:<value>` — no numeric IDs. The two never match, and the failure is an authentication error that says nothing about why.
>
> Create the credential **without** the owner/repository ID fields.

### The reaper must not be able to delete anything

This is the part to get right, because the failure mode is not a broken lab — it is a scheduled job with standing authority to delete resource groups in your subscription, triggered by a workflow file that anyone with push access can edit.

The default reaper stops labs, and stopping needs no delete permission at all. So the identity is given a **custom role that contains no delete action**:

```
Microsoft.Resources/subscriptions/resourceGroups/read
Microsoft.Resources/tags/write                              # maintain lifecycle tags
Microsoft.Compute/virtualMachines/read
Microsoft.Compute/virtualMachines/instanceView/read
Microsoft.Compute/virtualMachines/deallocate/action
Microsoft.Compute/virtualMachines/start/action
Microsoft.DesktopVirtualization/hostPools/read
Microsoft.DesktopVirtualization/hostPools/sessionHosts/read
Microsoft.DesktopVirtualization/hostPools/sessionHosts/write   # drain mode
Microsoft.DesktopVirtualization/scalingPlans/read
Microsoft.DesktopVirtualization/scalingPlans/write             # disable the plan
```

The built-in combination (`Virtual Machine Contributor` + `Desktop Virtualization Contributor`) is the tempting shortcut and is wrong: it cannot delete a resource group, but it *can* delete individual VMs, which is enough to ruin a lab by accident. The custom role cannot delete a thing.

`-OnExpiry Destroy` therefore cannot run under the default identity, by construction. It requires a second, more privileged federated credential bound to a **protected GitHub environment** with a required reviewer — so automatic destruction is possible, but only behind an explicit human approval. That is the right shape for an unattended job whose worst outcome is deleting someone's work.

---

## Cost estimation

Cost is **estimated live** rather than read from Cost Management, because Azure cost data lags 8–24 hours and a management tool that reports yesterday's number for a lab you started this morning is worse than useless — it reads as zero.

Two inputs, neither of which needs the durable store:

**Rates** come from the Azure Retail Prices API (`https://prices.azure.com/api/retail/prices`) — public, unauthenticated, no key, no module. Filter on `armRegionName`, `armSkuName`, `priceType eq 'Consumption'`; `retailPrice` is the hourly figure. Rates are cached per session; they do not move within a run.

**Compute hours** accumulate in tags, maintained by the only two commands that change power state:

- `Start-AvdLab` stamps `avdlab-running-since`
- `Stop-AvdLab` adds the elapsed stretch to `avdlab-compute-hours` and clears `avdlab-running-since`

Current cost is then `avdlab-compute-hours + (now - avdlab-running-since)` × rate, plus the fixed drip of the NAT gateway, public IP and storage. No store, no Activity Log query, no new dependency.

**Where this is wrong, and why that is acceptable:** if someone deallocates a VM by hand in the portal, the tag over-counts until the next `Stop-AvdLab`. The number is labelled an estimate, it errs high, and erring high on a cost display is the safe direction. Reconstructing true uptime from the Activity Log is the accuracy upgrade if the estimate ever proves misleading in practice — it is free and retained 90 days, but it is a second mechanism to maintain and is not worth it until the simple one demonstrably fails.

---

## What changes in existing code

| File | Change |
| --- | --- |
| `avdlab.bicepparam` | Names become templates over `labName`; `storageAccountName` is derived, not supplied |
| all 8 modules | Accept `labName`; apply the `avdlab-*` tag set |
| `storage.bicep` | Derive the storage account name |
| `Deploy-AvdLab.ps1` | `-LabName`, `-ExpiresIn`, `-Purpose`; write tags; drop the storage-name availability pre-flight (the name is derived now, so it cannot collide) |
| `Remove-AvdLab.ps1` | `-LabName`; report final estimated cost before deleting |
| `Test-AvdLabDeployment.ps1` | `-LabName`; resolve names from tags |
| `AvdLab.Tests.ps1` | Naming-scheme tests; lab-name validation; the 15-character computer-name limit |

New files:

| File | Purpose |
| --- | --- |
| `scripts/Get-AvdLab.ps1`, `Stop-`, `Start-`, `Set-`, `Reset-` | The lifecycle verbs |
| `scripts/Invoke-AvdLabReaper.ps1` | Runs unattended; callable by hand for a dry run |
| `.github/workflows/reaper.yml` | Scheduled execution, OIDC login |
| `bicep/modules/reaperrole.bicep` | The delete-free custom role definition, deployed once at subscription scope |

Archiving to the durable store (as-built on deploy, final cost on teardown) attaches to these same two scripts if and when the store is built. It is deliberately absent above.

The deployment path itself does not change shape. This is additive.

---

## Explicitly out of scope

Holding the line, since this is the change most likely to make the repo unreadable in one sitting:

- **Day-2 AVD operations** — killing sessions, adding users, host health triage. A different job.
- **A scenario library** — multiple selectable lab configurations. Orthogonal, and worth doing separately if at all.
- **Per-attendee fleets** — bulk stamping, quota-aware batching, parallel deployment.
- **Self-service** — any interface other than your CLI. No portal, no API, no auth model.
- **Cross-subscription management** — one subscription, so `Get-AzResourceGroup` suffices and Resource Graph stays out of the dependency list.
- **Managing Hard Mode labs.**

---

## Decisions

**Reaper runs in GitHub Actions.** Scheduled workflow, OIDC, no stored secrets, no Azure infrastructure to host it. Retires the unbuilt `AlertAndDelete` guardrail mode, which it supersedes.

**Cost is estimated live**, from the Retail Prices API and tag-accumulated compute hours, rather than read from Cost Management with its 8–24 hour lag.

**`labName` defaults to `lab`**, so existing forks keep working on update.

**The durable store is deferred, not rejected.** You were unsure, and the position this spec takes is that you do not need to decide yet — the sequencing already protects you:

- The other three decisions shrank what the store was for. Live cost estimation means there is no cost history to persist from an API, and GitHub Actions retains workflow run logs, so reaper lifecycle events already have a durable-enough home.
- Tags are the source of truth regardless. The store is an archive, never consulted to decide what exists, so bolting it on at step 5 requires no rework of steps 1–4.
- Steps 1–4 deliver the entire operational win — several labs, inventory, stop paying for idle ones — with no store at all.

So: build the core, run real labs for a few weeks, and the question answers itself with evidence instead of speculation. What you would lose in the meantime is history for labs torn down before the store exists, which is a small and bounded cost.

**One observation that changes the trade, though.** The original argument against a control plane was that it breaks the "one resource group, delete it and you're done" story. Choosing GitHub Actions means that story is *already* gone the moment management is switched on: the reaper needs a persistent Entra app registration, a federated credential and a custom role definition, none of which live in a lab resource group. A storage account alongside them is marginal rather than a new category of thing.

What actually protects the teaching story is that **management is opt-in**. A fork that never sets `-ExpiresIn` and never enables the workflow has no control plane, no reaper identity, and the same single-resource-group teardown as today. That, rather than avoiding the store, is the thing worth holding onto.

### Still open

Nothing blocking. Revisit the store at step 5.

---

## Build order

Reordered from the first draft: with the store deferred and the reaper confirmed, unattended expiry is worth more than archival.

1. **Lab naming and tags** across the modules — everything else depends on identity existing
2. **`Deploy-AvdLab -LabName`** + tag writing; confirm two labs genuinely coexist in one subscription
3. **`Get-AvdLab`** — inventory from tags, with the live cost estimate
4. **`Stop-AvdLab` / `Start-AvdLab`** — the four-step sequence, and the state detection that proves it actually stopped
5. **`Set-AvdLab`, `Reset-AvdLab`** — extend, retag, clean profiles
6. **`Invoke-AvdLabReaper`** + the custom role, federated credential and scheduled workflow
7. **Control-plane store** — deferred; revisit only if the missing history proves to hurt

Steps 1–4 are the useful core: after them you can run several labs and stop paying for the idle ones. Step 6 is what makes it unattended. Step 7 may never be needed.

**Suggested stopping point for a first pass: step 4.** It is self-contained, needs no new Azure identity or workflow, and is the point at which the tool stops being a deployment script.
