---
title: "Readiness check: what it reads and why"
summary: "The read-only check before the platform stage: every check, the right it needs, and what porting it from nerdio-hcl changed"
topic: readiness
status: built-offline
last_reviewed: 2026-10-22
---

# Readiness check: what it reads and why

Adapted from nerdio-hcl's readiness engine (Apache-2.0, commit `75f59bc`; see
[CREDITS.md](../../CREDITS.md)). Tested offline against recorded `az` answers shaped the way ARM
returns them (empty properties left out); it has not run against a real subscription yet.

```bash
python3 scripts/schema/answers.py init      # once
python3 scripts/preflight.py                # console report
python3 scripts/preflight.py --format md    # a report to paste into a ticket
```

In the pipeline, run the Deploy workflow with stage `preflight`: it signs in as the plan
identity, never changes anything, saves the JSON result in the `plans` container and turns the
job red on NO-GO or INCOMPLETE.

Every `az` call goes through one guard that allows only `show`, `list`, `list-*` and
`az rest --method get`; anything else raises before it runs, and a test holds every check to it.
Output masks GUIDs, the subscription, tenant and user names, and resource and group names
(`--names` shows them).

Verdicts: **GO**, **GO WITH WARNINGS** (warnings or things to confirm), **NO-GO** (anything
failed, exit 1), **INCOMPLETE** (every identity or subscription check came back no-access, exit
3). `--strict` makes a warning exit 1.

## Checks

| ID | Check | Right needed | Reads with |
|---|---|---|---|
| `op.cloud` | Azure cloud: AzureCloud only for now | none | `az cloud show` |
| `op.tools` | Terraform 1.11+, python3 3.9+, az, jq, git | none | PATH |
| `op.signin` | Signed in to az | none | `az account show` |
| `id.sub_owner` | Owner, or Contributor plus Role Based Access Control Administrator | Reader | `az role assignment list` |
| `id.groups` | Every user and admin group exists, by ID or by exactly one display name | Directory read | `az ad group list` (filtered by ID or name) |
| `id.avd_principal` | The Azure Virtual Desktop service principal is in the tenant | Directory read | `az ad sp list` (filtered by app ID) |
| `sub.providers` | The platform root's providers are registered (the list is read from its `versions.tf`) | Reader | `az provider list` |
| `sub.region` | The region is open to the subscription | Reader | `az account list-locations` |
| `sub.encryption_at_host` | The EncryptionAtHost feature is registered, when it's on | Reader | `az feature show` |
| `sub.policy_list` | Enforced policy assignments, for a person to read | Reader | `az policy assignment list` |
| `sub.licenses` | Users need an eligible license (always for a person to confirm) | none | none |
| `net.overlap` | The address range against the subscription's other VNets | Reader | `az network vnet list` |
| `net.hub` | The hub is readable, doesn't overlap, and you can peer it | Reader on the hub | `az network vnet show` |
| `net.private_dns` | privatelink zones for file, blob and Key Vault that already exist elsewhere | Reader | `az network private-dns zone list` |
| `net.egress` | Exactly one way out: the NAT gateway or a firewall route | none | answers |
| `avd.vm_size` | The size is offered and not restricted | Reader | `az vm list-skus` |
| `avd.vm_features` | The size supports Trusted Launch, Premium SSD and encryption at host | Reader | `az vm list-skus` |
| `avd.zones` | The size is offered in the zones asked for | Reader | `az vm list-skus` |
| `avd.vcpu` | Family and regional vCPU quota for `host_count` hosts | Reader | `az vm list-usage` |

A test fails when a check is registered but missing from this table.

## What porting it changed

- **Removed:** everything that checks for Nerdio Manager (license, App Service and SQL capacity,
  app registration and admin consent rights, the post-install and post-wizard stages, feature
  flags and the standalone mode).
- **New for AVD:** groups, the AVD service principal, encryption at host (feature and size),
  Trusted Launch and Premium SSD support, zones, the egress choice.
- **Providers can't drift:** the check reads `resource_providers_to_register` from the platform
  root instead of keeping its own list. A missing provider is a warning, not a failure: a Cloud
  Shell run as Owner registers it, but the pipeline's read-only plan identity can't, so its
  first plan fails until it's registered.
- **Quota counts `host_count`,** not users divided by sessions: the platform stage builds exactly
  that many hosts.

## Gotchas

- **SKU zone restrictions** come as `restrictions[].type == "Zone"` with
  `restrictionInfo.zones`; a size can be offered in the region but not in every zone for your
  subscription.
- **`TrustedLaunchDisabled`** is only present on sizes that can't use it; its absence means
  supported. `PremiumIO` and `EncryptionAtHostSupported` are the other way round.
- **"Not there" and "can't read" look the same to `az ... show`:** both just fail. The group and
  service principal checks use a filtered `az ... list` instead, which returns an empty list when
  the object doesn't exist and fails only when the directory can't be read, so a missing right
  comes back as no-access, not as a NO-GO.
- **A size restricted for the subscription** (`restrictions[].type == "Location"`) makes the
  feature, zone and quota checks skip, so the report doesn't call an unusable size fine.
- **Masking must not break the fixes.** Links and Microsoft's public IDs (`.github/public-ids.txt`)
  are left alone, and an account named only a word the report itself uses (Azure, Network) isn't
  masked, or every link and role name would be.
- **Signed in as a service principal** (the pipeline), the deployer-rights and hub-rights checks
  come back as "manual": the apply identity holds those roles by design.

Verify checks (after the apply: hosts registered and available, a first sign-in) come with the
first sandbox run, when there is something real to read.
