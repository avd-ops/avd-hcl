---
title: "Lab topology bootstrap"
summary: "Terraform module and root for the 4-subscription ALZ lab topology, MCA vending, and per-subscription budgets"
topic: platform
status: plan
last_reviewed: 2026-11-15
---

# Lab topology bootstrap

`modules/lab-topology` and `environments/example/00-lab-topology` implement the primary 4-subscription ALZ hub-and-spoke topology defined in [avd-ops decision 0019](https://github.com/avd-ops/avd-ops/blob/main/docs/knowledge/decisions/0019-multi-subscription-multi-tenant-lab-topology.md).

## What it manages

- **Management Group hierarchy:** `platform` (`connectivity`, `management`), `landing-zones`, `sandbox`, and `decommissioned`.
- **Subscription placement or MCA vending:** Set `vend_subscriptions = true` with an MCA `billing_scope_id` to vend `platform-connectivity`, `platform-management`, `lz-avd-workload` (plus optional `lz-avd-workload-2` via `enable_second_workload_spoke = true`), and `sandbox-ci` via `azurerm_subscription`. Any subscription already listed in `existing_subscription_ids` is reused in place and only missing subscriptions are vended.
- **Spend guardrails:** Attaches a monthly `azurerm_consumption_budget_subscription` (50% Actual, 80% Actual, 100% Forecasted) to every active subscription.
- **CI isolation:** Optional `ci_principal_id` grants `Contributor` scoped to the `sandbox` Management Group for `sandbox-ci` OIDC runners.
- **Subscription baseline (`modules/subscription-baseline`):** Registers the required Azure Resource Providers (`Microsoft.DesktopVirtualization`, `Microsoft.Compute`, `Microsoft.Network`, `Microsoft.Storage`, `Microsoft.KeyVault`, `Microsoft.OperationalInsights`, `Microsoft.ManagedServices`, `Microsoft.Quota`) on each target subscription.
- **T2T Azure Lighthouse (`modules/t2t-lighthouse` and `environments/example/00-t2t-lighthouse`):** Registers providers on the secondary tenant's `t2t-lab` subscription and creates the `azurerm_lighthouse_definition` and `azurerm_lighthouse_assignment` delegating access to the primary lab tenant.
- **Entra Cross-Tenant Access (`modules/cross-tenant-access`):** Configures partner B2B collaboration, inbound MFA/device trust, and automatic user consent settings via `msgraph_resource` (`policies/crossTenantAccessPolicy/partners`).
- **Hub-to-spoke peering (`modules/hub-spoke-peering`):** Completes the `platform-connectivity` hub side of multi-subscription peering (`azurerm_virtual_network_peering`) and links central Private DNS zones to spoke VNets (`lz-avd-workload`).

## Manual prerequisites

See [multi-tenant-lab-bootstrap](https://github.com/avd-ops/avd-ops/blob/main/docs/knowledge/getting-started/multi-tenant-lab-bootstrap.md) for the one-time Portal steps (secondary Entra tenant CAPTCHA, Tenant Root Group elevation toggle, and MCA subscription cap ticket).
