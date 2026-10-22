---
title: "Port plan: native AVD with the HashiCorp stack"
summary: "Plan to port nerdio-hcl's approach to Terraform that deploys and operates AVD directly, with no Nerdio Manager in the path; phase 1 built offline"
topic: roadmap
status: plan
last_reviewed: 2026-10-21
---

# Port plan: native AVD with the HashiCorp stack

The plan for this kit: the approach of [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl)
(Apache-2.0, read at `75f59bc`) ported to Terraform and Packer (decision 0004: no Vault server) that deploy and operate
Azure Virtual Desktop directly, with no Nerdio Manager in the path, following the estate design of
[avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) (MIT). The same plan was first
recorded in the AVD family's knowledge base ([port plan](https://github.com/avd-ops/avd-second-brain/blob/main/docs/knowledge/landing-zone/terraform-port-plan.md),
[decision 0025](https://github.com/avd-ops/avd-second-brain/blob/main/docs/knowledge/decisions/0025-avd-native-terraform-kit.md)). This copy is the one kept
current; decisions made since are in [decisions/](decisions/).

Why a separate repo: the AVD family's repos use Bicep and PowerShell only, and their lane rule
([decision 0012](https://github.com/avd-ops/avd-second-brain/blob/main/docs/knowledge/decisions/0012-family-format-project-lanes.md)) keeps HCL out of them.
This kit is the HCL lane's native-AVD repo, so nothing in the AVD repos changes for it
([decision 0001](decisions/0001-native-avd-with-the-hashicorp-stack.md)).

## 1. Maps one to one

Design that carries over almost unchanged, minus the Nerdio parts.

| nerdio-hcl piece | In the AVD-native kit | Notes |
|---|---|---|
| Eight phases: discover, prepare, configure, bootstrap, deploy, wizard, verify, handover | Same eight. "Wizard" becomes **first sign-in and assignment** (no vendor wizard exists) | Phase list in `schema/parameters.json` |
| One parameter schema driving chat, `init` and the Actions form | Same shape, new parameters (section 3) | Discover questions (environment, identity model, users, workload, region) carry over as is |
| `modules/foundation` (resource groups, provider registration, Log Analytics) | Same | Adds `Microsoft.DesktopVirtualization` and AVD Insights prerequisites |
| `modules/network` (spoke, subnets, NSGs, NAT gateway, private DNS, hub peering) | Same, minus the App Service subnet | Landing zone lesson 0001 (NAT gateway public IP zones) and 0010 (private endpoint resource group) apply |
| `modules/fslogix-storage` (Premium Azure Files, private endpoint, Entra Kerberos / AD DS / Entra DS, SMB RBAC) | Same, plus the landing zone's SMB channel encryption fix | Channel encryption must allow AES-128-GCM with AES-256-GCM for Entra Kerberos (landing zone lesson 0028) |
| `modules/image-gallery` + `packer/avd-win11` with WDOT | Same gallery and Packer build | See the WDOT pin difference in question 7 |
| `modules/deploy-pipeline` (state storage, plan and apply OIDC identities, required-reviewer environment, saved-plan hash) | Same | Keyless; apply only after a named reviewer approves |
| `modules/github-repo` (labels, read-only token, ruleset) | Same | |
| Least privilege, `docs/access.md`, constrained RBAC Administrator, PIM for one-time steps | Same rule; a much smaller Graph footprint | No vendor app registration, so no `Application.ReadWrite.All` or consent roles by default |
| Read-only readiness engine (check registry, stable IDs, Reader-only, `no-access` and `skipped`, masked JSON) | Same engine; Nerdio checks removed | Keeps `op.*`, `sub.providers`, `sub.region`, `sub.policy_list`, `net.*`, `avd.vcpu`, `avd.vm_size`, `avd.licenses`, `id.sub_owner`, `id.entra_roles`, `id.domain_join_account` |
| Key Vault for secret hand-off, ephemeral reads, write-only attributes | Same, for the few secrets left (local admin, domain join account) | Operators never type them (landing zone decision 0004 does the same in Bicep) |
| Cloud Shell baseline, `cloudshell-bootstrap.sh`, Codespaces optional | Same | iPad is the test case |
| `terraform test`, tflint, gitleaks, no tracked tfvars or state | Same | |
| KB format, decisions, known errors, curator | Same family format | |

## 2. Must be redesigned

| Area | Why it changes | Redesign |
|---|---|---|
| Ownership of AVD objects (nerdio-hcl 0002: "Nerdio owns AVD objects", never `azurerm_virtual_desktop_*`) | Reversed: nothing else owns them now | Terraform owns host pools, app groups, workspaces, scaling plans and their associations through `azurerm`. Runtime state that the service changes (scaling, drain, power) is ignored in `lifecycle` so Terraform and autoscale don't fight |
| Two stages, two states (platform, then Nerdio config) | Stage 2 existed only because Nerdio had to be running first | One **platform** stage plus an **estate** stage per host pool (so a pool can be planned and replaced alone), plus an **image** stage |
| Session host lifecycle | Nerdio created, resized and replaced hosts | Option A: Terraform VMs (count or for_each) with Run Command / extensions for join and agent registration, rotation by name generation, like the landing zone's blue/green. Option B: the service's own **session host configuration and session host update** (preview, pooled only, through `azapi`). Recommend A as default, B as an opt-in for pooled pools (question 5) |
| Registration token | Nerdio handled it | Short expiry set on the host pool through ARM, token read ephemerally and written once to the agent install run command, never in state ([platform.md](platform.md)) |
| Readiness checks | Nerdio-specific ones go | Drop `sub.nerdio_license`, `sub.app_service`, `sub.sql`, `id.app_registration`. Add AVD ones (section 3) |
| Chat assistant's tool surface | It drove a two-stage Nerdio flow | Same assistant design (Container Apps, Entra sign-in, Claude API by workload identity federation, can start plans, can't approve); new questions and explanations |
| Hardening module | Built for Nerdio's App Service, SQL and Key Vault | Private endpoints for profile storage, Key Vault and the AVD private link (optional), not for a management app |
| `Mastercard/restapi` gap fillers | No vendor API left | `azapi` for anything `azurerm` lacks (session host configuration, newer AVD properties) |

## 3. New: what Nerdio used to do

| Nerdio did | Native replacement | Built how |
|---|---|---|
| Auto-scale profiles (CPU triggers, burst, min active, scale-in messaging) | **AVD scaling plans** (schedules, ramp-up/peak/ramp-down/off-peak, capacity thresholds, drain and notify), pooled and personal | `azurerm_virtual_desktop_scaling_plan` + host pool association; the service principal role assignment it needs. Dynamic autoscale (create and delete hosts) only with session host configuration (preview) |
| Image management: import, set as image, rollout | Compute Gallery versions, pinned by version in tfvars; rollout by host rotation (or session host update) | Packer stage behind approval; a new version is a PR that changes the pin |
| Scripted actions | Run Commands (protected parameters), image-time Packer provisioners | Terraform `azurerm_virtual_machine_run_command`; nothing ad hoc from chat |
| User-driven provisioning for personal desktops | Personal host pools with automatic assignment plus Start VM on Connect | Start VM on Connect role assignment for the AVD service principal; pre-provisioned hosts sized by a parameter. A request-a-desktop flow is a gated workflow, later |
| Power management and cost savings | Scaling plans, auto shutdown, budgets | Budget and alert per environment; tags for cost |
| Monitoring and alerts | **AVD Insights**: Log Analytics, the data collection rule, diagnostic settings on host pools, app groups and workspaces, Azure Monitor Agent | `azurerm_monitor_data_collection_rule` and association; note session host update does not install the agent itself |
| Desktop and RemoteApp assignment | App groups + `Desktop Virtualization User` on Entra groups; `Virtual Machine User Login` for Entra-joined hosts | `azurerm_role_assignment`, groups from the schema |
| Auto-heal and broken host handling | No native auto-heal | Out of the first build; read-only health checks in the verify phase |
| Its own dashboards and reports | Azure portal, AVD Insights workbooks | Link them in the handover runbook |
| New readiness checks | | `avd.region` (AVD metadata location), `avd.host_pool_limits`, `avd.scaling_plan_role`, `id.vm_user_login`, `net.avd_endpoints` (required URLs from the session host subnet, read-only where possible) |

## 4. How it relates to avd-landing-zone

The landing zone already deploys and operates this in Bicep: control plane, session hosts, FSLogix,
AVD Insights, Azure Image Builder with WDOT, blue/green rotation, auto shutdown, backup, Bastion,
budgets, readiness preflight and the portal, with 30 lessons from real runs. A Terraform kit is a
second engine for the same estate shape. Options (question 2):

1. **Separate repo, shared contracts (recommended).** The kit reads the same target-state
   manifest (C14) the landing zone reads, with its own capability list, and keeps its own
   parameter schema. avd-current-state can check a kit-built estate read-only. The landing zone
   and avd-current-state don't change and never depend on the kit, so they stay a self-contained
   pair; the brain and avd-swarm are not involved.
2. **Shared parameter schema** used by the landing zone's portal and the kit. More reuse, but the
   landing zone would have to adopt a schema it doesn't need, so it fails the self-contained rule
   for now.
3. **Parallel option inside the landing zone.** Blocked by the lane rule, and two engines in one
   repo double every test and review.

Lessons and design facts from the landing zone (MIT) are reused by link and in our own words;
where a fix is the same (lesson 0028, lesson 0021 on ARM omitting empty properties, lesson 0024
on quota), the kit gets its own test.

## 5. Build or adopt

Adopt only what is the best and open source, otherwise build ([decision 0002](decisions/0002-reuse-with-credit.md)).
The prior-art check of 2026-10-21 (AVD family KB's `kb-prior-art` workflow) found:

- **Azure Verified Modules for Terraform** (Microsoft, MIT), all updated 2026-10-21: resource
  modules `avm-res-desktopvirtualization-hostpool`, `-applicationgroup`, `-workspace`,
  `-scalingplan`, and pattern modules `avm-ptn-avd-lza-managementplane` and
  `avm-ptn-avd-lza-insights`. These are the first candidates to wrap, the way avd-landing-zone
  wraps the AVM Bicep modules. Checked in phase 1: every one requires azurerm < 5.0 and pulls the
  modtm telemetry provider, so the kit writes its own thin modules on azurerm 5 for now
  ([decision 0003](decisions/0003-own-modules-on-azurerm-5.md), proposed).
- **Community labs** (pooled, Entra-joined, FSLogix, scaling plan in Terraform) exist, the largest
  around 90 stars. Prior art only: read for facts, not adopted.
- Nothing found does the guided phases, the shared schema or the gated pipeline for native AVD;
  those come from nerdio-hcl.

## 6. Open questions for the owner

1. **Where does the code live?** Answered 2026-10-21: here, a private repo for now, Apache-2.0,
   separate from the AVD repos. The earlier Bicep lab kit in this repo was removed (it stays in
   git history at `de2b9bc`; its useful parts were already ported to avd-landing-zone). Scope:
   Terraform, Packer and Vault, plus Ansible only if a decision record shows it earns its place.
   Later the same day: no Vault server; Key Vault holds secrets (decision 0004).
2. **How does it relate to the landing zone?** Separate repo with shared contracts (the
   recommendation; the owner said "go" to the recommendations on 2026-10-21).
3. **Scope of the first build:** pooled, Entra-joined, one host pool, FSLogix on Azure Files,
   marketplace image. Personal pools, AD DS and the custom image come later.
4. **Images:** Packer, with nerdio-hcl's build reused with attribution.
5. **Session hosts:** Terraform-managed VMs by default; session host configuration and update
   (preview, pooled only) as a later opt-in.
6. **The chat assistant:** engine, CLI and Actions form first, chat in phase 4; the schema is
   built for both.
7. **WDOT pin:** follows the landing zone's fix for the silent first-run failure, plus a check
   of the WDOT event log.
8. **Sandbox runs:** one batch per phase, each with a written estimate and the owner's exact
   `go batch <id> $<total>`.

## 7. Phased order

Each phase is one PR (or a small set) with `terraform test`, tflint and gitleaks green before any
sandbox run.

0. **Decide and set up.** Owner answers the open questions. Prior-art check (done). This repo:
   lab kit removed, Apache-2.0, NOTICE and CREDITS, guardrails, KB skeleton, CI. Family KB tooling
   and family.yaml rows follow when the repo goes public.
1. **Engine core, offline.** Built 2026-10-21 ([platform.md](platform.md)): parameter schema and
   its check, foundation, network, FSLogix storage, Key Vault, control plane (host pool, desktop
   app group, workspace, assignments, and the scaling plan pulled forward from phase 3), session
   hosts from a marketplace or gallery image, AVD Insights. `terraform test` with mocked
   providers only. Moved to phase 2: `init` (the command that writes tfvars from the schema) and
   tflint.
2. **Gated pipeline and readiness.** 2a built 2026-10-22 ([pipeline.md](pipeline.md)): deploy
   pipeline (state storage, plan and apply identities, reviewer gate, saved-plan hash), the
   `00-pipeline` root, the deploy workflow, the bootstrap script, `init` and `render` from the
   schema, and tflint. 2b built 2026-10-22 ([readiness.md](readiness.md)): the readiness engine
   with the Nerdio checks removed and the AVD ones added, also a `preflight` stage in the Deploy
   workflow. Verify checks come with the first sandbox run, after an estimate and the owner's go.
3. **Day 2.** Scaling plans, auto shutdown and budget, host rotation, Packer image stage and
   gallery pin, personal pools with Start VM on Connect.
4. **Chat front door.** The assistant over the same schema and pipeline, handover runbook.
5. **Later.** AD DS and Entra DS join, hardening (private endpoints, self-hosted runner), session
   host configuration opt-in, RemoteApp groups, Azure Government.
