---
status: proposed
date: 2026-10-21
decision-makers: [owner]
---

# 0003. Own thin modules on azurerm 5, not Azure Verified Modules, for now

## Context and Problem Statement

Phase 1 needs Terraform modules for the AVD control plane, session hosts, profile storage, Key
Vault and monitoring. The prior-art check found Azure Verified Modules (AVM) for Terraform for the
host pool, application group, workspace and scaling plan, all updated 2026-10-21. nerdio-hcl's
modules, which this kit reuses for the foundation, network and profile storage, are written for
azurerm 5. Which modules does the kit build on?

What was checked, on 2026-10-21 (latest releases: hostpool 0.5.0, applicationgroup 0.3.0,
workspace 0.3.0, scalingplan 0.3.0):

- Every one of them requires `hashicorp/azurerm < 5.0` (and `azure/azapi ~> 2.12`). The latest
  azurerm is 5.10.0, and the reused nerdio-hcl modules require `>= 5.0`. One root can hold only one
  azurerm version, so AVM and the reused modules can't live in the same root today.
- Each AVM module also pulls the `azure/modtm` provider, which sends module telemetry to
  Microsoft unless a variable turns it off.
- AVM has no Terraform module for the session host VMs with the AVD run commands, and the
  landing zone's design (two run commands, Entra join, AMA with the AVD Insights rule) needs one
  anyway.

## Considered Options

- Own thin modules on azurerm 5, reusing nerdio-hcl's and following the landing zone's design
- AVM modules on azurerm 4, with the reused nerdio-hcl modules ported back to azurerm 4
- AVM for the control plane in a separate root on azurerm 4, own modules elsewhere on azurerm 5

## Decision Outcome

Proposed: "Own thin modules on azurerm 5", because it keeps one provider version across the
kit, needs no telemetry provider, and the AVD resources are small enough that a module is a thin
layer over the azurerm resources. Proposed with phase 1; it becomes accepted when the owner merges
the pull request that brings it.

- Each module follows the landing zone's Bicep module of the same role, with a source header and
  a CREDITS row, and carries its lessons as `terraform test` runs.
- Revisit when the AVM AVD modules support azurerm 5: swapping the control plane module for AVM
  then is a change behind the same inputs and outputs.

### Consequences

- Good, because one azurerm version and no extra provider in any root.
- Good, because each module is short and reads like the landing zone's design.
- Bad, because the kit maintains what AVM would maintain, and doesn't get AVM's interfaces
  (role assignments, private endpoints, locks) for free.
- Neutral, because the modules keep AVM-like inputs where they overlap, so a later switch costs
  little.
