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

Lab names are constrained to **3–12 characters, lowercase letters and digits**. That is not arbitrary: the Windows computer name limit is 15 characters, and `vm-<labName>-<n>` must fit inside it.

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

**This introduces a genuine cost:** a tool whose selling point is "one resource group, delete it and you're done" now has a second, persistent resource group. That is a real regression in the teaching story and should be acknowledged rather than hidden. Mitigations: the control plane is created on demand rather than assumed, everything works without it in a degraded mode (you lose history, not function), and `Remove-AvdLabControlPlane` exists as an explicit escape hatch.

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

**Where it runs is an open decision** (see below). It must run unattended, which means it cannot depend on your laptop.

A lab is never reaped silently. Every action writes a lifecycle event to the store and sends a notification, reusing the action group `monitoring.bicep` already deploys.

---

## What changes in existing code

| File | Change |
| --- | --- |
| `avdlab.bicepparam` | Names become templates over `labName`; `storageAccountName` is derived, not supplied |
| all 8 modules | Accept `labName`; apply the `avdlab-*` tag set |
| `storage.bicep` | Derive the storage account name |
| `Deploy-AvdLab.ps1` | `-LabName`, `-ExpiresIn`, `-Purpose`; write tags; publish the as-built to the store; drop the storage-name availability pre-flight |
| `Remove-AvdLab.ps1` | `-LabName`; capture final cost to the store before deleting |
| `Test-AvdLabDeployment.ps1` | `-LabName`; resolve names from tags |
| `AvdLab.Tests.ps1` | Naming-scheme tests; lab-name validation; the 15-character computer-name limit |

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

## Open decisions

1. **Where the reaper runs.** GitHub Actions on a schedule with OIDC federated credentials is the leading option: the repo already has a commented-out OIDC job, it stores no secrets, and it needs no new Azure infrastructure. The alternative is an Azure Automation account, already sketched for the unbuilt `AlertAndDelete` mode — more durable, but it is more infrastructure inside the thing being managed. **Recommendation: GitHub Actions**, and retire the `AlertAndDelete` design in favour of the reaper, which supersedes it.

2. **Whether the control plane is required or optional.** Optional-with-degradation is proposed above, but that means two code paths for every store write. Making it required is simpler to build and harder to explain.

3. **Cost figures are not real-time.** Azure cost data lags 8–24 hours, so `Get-AvdLab` cost is always yesterday's. Either show it with the lag stated, or compute an estimate from VM size and uptime. Estimating is more useful and more likely to be wrong.

4. **What happens to the existing single-lab workflow.** Threading `labName` everywhere is a breaking change to the parameter file. Either default `labName = 'lab'` so the current workflow keeps working, or make it mandatory and force the decision. **Recommendation: default it**, since the repo is public and a fork should not break on update.

---

## Build order

1. Lab naming and tags across the modules — everything else depends on identity existing
2. `Deploy-AvdLab -LabName` + tag writing; confirm two labs coexist in one subscription
3. `Get-AvdLab` — inventory from tags, no store yet
4. `Stop-AvdLab` / `Start-AvdLab` — the four-step sequence, and the state detection that proves it worked
5. Control-plane store + as-built publishing
6. `Set-AvdLab`, `Reset-AvdLab`
7. `Invoke-AvdLabReaper` + scheduled execution

Steps 1–4 are the useful core: after them you can run several labs and stop paying for idle ones. Everything after is convenience and durability.
