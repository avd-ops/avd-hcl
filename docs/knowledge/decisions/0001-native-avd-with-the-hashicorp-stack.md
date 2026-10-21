---
status: accepted
date: 2026-10-21
decision-makers: [owner]
---

# 0001. Native AVD with the HashiCorp stack, in its own repo, beside avd-landing-zone

## Context and Problem Statement

nerdio-hcl showed a guided, keyless, gated way to deploy Azure Virtual Desktop with Terraform and
Packer, but every AVD object in it goes through Nerdio Manager. avd-landing-zone deploys and
operates native AVD in Bicep, and the AVD family's repos keep HCL out by rule. Where does a
native-AVD kit built on the HashiCorp stack live, and how does it relate to the landing zone?

## Considered Options

- Its own repo, separate from the AVD family's repos, reading the same contracts as the landing zone
- Allow HCL in one AVD family repo, as a parallel option to the Bicep landing zone
- A third, new repo, keeping this repo's earlier Bicep lab kit on main

## Decision Outcome

Chosen option: "Its own repo" (this one), because no AVD repo, lane rule or guard has to change,
and avd-landing-zone and avd-current-state stay a self-contained pair that never depends on it.

- Scope: Terraform for the estate, Packer for images, Vault or OpenBao where a secret store is
  needed ([0004](0004-hashicorp-community-editions.md): Vault Community Edition). Ansible only if a
  later decision record shows HCL can't do the job.
- No Nerdio in the path: Terraform owns host pools, app groups, workspaces, scaling plans and
  session hosts directly.
- The earlier Bicep lab kit is removed from main; it stays in git history at `de2b9bc`, and its
  useful parts were already ported to avd-landing-zone.
- The repo stays private until the owner makes it public; until then no public repo names it.

### Consequences

- Good, because the AVD family's guards stay as they are.
- Good, because the landing zone's lessons carry over here as tests, by link.
- Bad, because two engines describe the same estate shape, so a design change in one is a
  question for the other.
- Neutral, because Terraform users who run Nerdio keep using nerdio-hcl.

## More Information

Plan: [port-plan.md](../port-plan.md). First proposed in the AVD family KB as decision 0025.
Still open there: how closely the kit follows the landing zone's contracts (plan question 2).
