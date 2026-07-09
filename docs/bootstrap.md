# Bootstrapping a subscription and tenant

`Initialize-AvdLabPrerequisites.ps1` tells you what's wrong. This tells you how to fix it.

The script registers resource providers and reports on everything else, because everything else is a procurement decision, a support ticket, or a tenant-wide security change — none of which a lab tool should make on your behalf. This runbook walks the manual half, in the order that fails fastest.

> **Read the [Security Defaults fork](#4-the-security-defaults-fork) before you spend money.** It is the one decision here with a lead time, and one of its two paths has a trap that only shows up weeks later.

---

## 0. Decide what kind of tenant this is

The answer changes the rest of the runbook, so decide first.

**A disposable demo tenant** — created for this lab, holds no real data, deleted afterwards. You can turn off Security Defaults and add no Conditional Access at all. Nothing requires MFA, Entra Kerberos works, and you spend nothing on identity licensing.

**A tenant you actually care about** — your own dev tenant, or anything with real accounts in it. You need Conditional Access to replace Security Defaults, which means Entra ID P1 or better, which means either a paid license or a trial with an expiry date you must plan around.

Nearly everyone reading this wants the first one. Create a fresh tenant. It is free, it takes ten minutes, and it removes every hard decision below.

---

## 1. Create the tenant and subscription

If you already have both, skip to step 2.

1. Create a Microsoft Entra tenant: [entra.microsoft.com](https://entra.microsoft.com) → **Manage tenants** → **Create**.
2. Create an Azure subscription in that tenant. A Free Trial or Pay-As-You-Go both work.
3. Note the **subscription ID** and **tenant ID**. You'll pass both to every script.

Neither ID is a secret in the "rotate it immediately" sense, but both go in your gitignored `avdlab.local.bicepparam` and never in a tracked file. See [CONTRIBUTING.md](../CONTRIBUTING.md).

**If you're using an existing subscription:** you don't need an empty one. Everything deploys into a dedicated resource group and touches nothing outside it. What you *do* need to check is inherited Azure Policy from a management group — mandatory tags or allowed-SKU restrictions will fail a deployment partway through, and the failure message rarely names the policy.

---

## 2. Elevate access — being Global Administrator is not enough

This one surprises people, and it surprises them at the worst moment.

**Microsoft Entra ID and Azure RBAC are separate access-control systems.** Being a Global Administrator in the tenant grants you exactly nothing in Azure. If you created the tenant *and* the subscription you're probably already Owner and can skip this. If someone handed you the tenant, or you're seeing "you do not have permission" on a subscription you appear to own, you need to elevate:

1. Azure portal → **Microsoft Entra ID** → **Manage** → **Properties**
2. Set **Access management for Azure resources** to **Yes**, and save
3. **Sign out and back in** — the token doesn't refresh on its own
4. Assign yourself **Owner** (or **Contributor** + **User Access Administrator**) on the subscription
5. Set the toggle back to **No**

That toggle grants you User Access Administrator at root scope (`/`) — every subscription and management group in the tenant. It is per-user, not tenant-wide. Turn it off when you're done; it exists to bootstrap access, not to hold it.

You need **User Access Administrator** (not just Contributor) because Lab Kit creates a role assignment: the demo group needs `Storage File Data SMB Share Contributor` on the FSLogix storage account, and granting a role requires the authority to grant roles.

---

## 3. Run the prerequisites check

Now let the script tell you where you stand.

```powershell
./scripts/Initialize-AvdLabPrerequisites.ps1 `
    -SubscriptionId <your-subscription-guid> `
    -TenantId <your-tenant-guid> `
    -OutputPath ./readiness.json
```

It registers the four resource providers (idempotent) and reports the rest. Work through whatever it flags using the sections below. Re-run it as often as you like.

Exit code is `1` only if it found a blocker. Items marked `[action]` don't fail the run — a quota increase already in flight is a legitimate state to be in.

---

## 4. The Security Defaults fork

**Entra Kerberos cannot work in a tenant with Security Defaults enabled.** This is the blocker, and it deserves the space.

FSLogix profiles live on an Azure Files share reached over SMB with Microsoft Entra Kerberos. The Kerberos ticket is acquired silently while the user logs on — there is no window, no prompt, nowhere to answer an MFA challenge. So the storage account's Entra application must be excluded from any MFA requirement. That exclusion is expressible *only* as a Conditional Access policy exclusion. And Security Defaults is all-or-nothing: it offers no per-app or per-user exclusion of any kind.

Security Defaults is **on by default for every tenant created since October 2019**, so assume it's on.

Only FSLogix is blocked. The host pool, app group, workspace, and autoscale all work fine regardless. If you're short on time you can demo everything except profile containers.

### Path A — disposable tenant: turn it off, add nothing

1. [entra.microsoft.com](https://entra.microsoft.com) → **Entra ID** → **Overview** → **Properties**
2. **Manage security defaults** → set to **Disabled**
3. Create no Conditional Access policies

Nothing now enforces MFA, so nothing blocks silent Kerberos ticket acquisition. `Set-AvdLabFSLogixAuth.ps1` will report *"No Conditional Access policies found; nothing to exclude"* and proceed.

This requires no Entra ID P1 and costs nothing. It also means the tenant has no MFA at all — which is why it belongs only in a throwaway tenant with no real data, a strong unique password on the admin account, and a short life.

### Path B — a tenant you care about: replace it with Conditional Access

1. Disable Security Defaults, as above
2. Immediately create Conditional Access policies to replace the protection you removed — the Microsoft-managed templates cover the same ground (MFA for admins, MFA for all users, block legacy authentication)
3. Exclude the storage account app from any policy that requires MFA for all applications:

   ```powershell
   ./scripts/Set-AvdLabFSLogixAuth.ps1 `
       -StorageAccountName <your-storage-account> `
       -TenantId <your-tenant-guid> `
       -ApplyConditionalAccessExclusion
   ```

   Without `-ApplyConditionalAccessExclusion` the script reports which policies block you and changes nothing. That's the default on purpose: editing a tenant's Conditional Access policies is not something a lab deployment should do to you unasked.

The app to exclude is named `[Storage Account] <your-storage-account-name>.file.core.windows.net`.

> ### ⚠️ The 30-day trial trap
>
> Conditional Access requires **Entra ID P1** or better. The **Entra ID P2 trial lasts 30 days.**
>
> If you start the trial today to unblock this lab, it expires roughly a month from now. If your demo is further out than that — and for the September WEUC session it is — you will be standing on stage with an expired license.
>
> What happens on expiry is worse than it sounds. Conditional Access policies are **not** disabled or deleted when the license lapses. They keep enforcing. You can view and delete them, but **you cannot edit them.** So an expired trial leaves you with an MFA-for-all-apps policy that still blocks Kerberos and that you can no longer add an exclusion to. The fix at that point is to delete the policy outright.
>
> Three ways out, in order of preference:
> - **Take Path A instead.** A disposable tenant needs no Conditional Access, so it needs no license.
> - **Buy Entra ID P1**, or use a tenant that already has it via M365 E3/E5/F1/F3 or Business Premium.
> - **Start the trial deliberately late**, within 30 days of the date you actually need it — and rehearse before you start it, using Path A in a separate tenant.

---

## 5. Windows 11 Enterprise multi-session licensing

The session hosts need use rights. One of these:

- Microsoft 365 E3, E5, A3, A5, F3, Business Premium, or Student Use Benefit
- Windows Enterprise E3 or E5
- Windows Education A3 or A5
- Windows VDA per user

**Or skip it entirely:** deploy into an **Azure Dev/Test subscription**, where AVD access rights are included for acceptance testing without a separate per-user entitlement. `Initialize-AvdLabPrerequisites.ps1` detects this from the subscription's `quotaId` and reports licensing as satisfied.

A fresh tenant has no licenses at all, so expect this to flag on a greenfield run. It's a procurement decision; no script can provision it.

---

## 6. vCPU quota

The default is 3 session hosts × `Standard_D4ads_v5` = **12 vCPU**, and the check covers both the per-family limit and the regional total.

A brand-new subscription can be quota-constrained on day one with nothing running. A quota increase is a support request, **not instant**, and not scriptable. If the check flags this, raise the request now — Azure portal → **Quotas** → **Compute**.

Alternatively, drop `sessionHostCount` to 2, which is still enough to demonstrate load balancing.

---

## 7. Create the demo user and group

Session hosts don't publish themselves to anyone. Create:

1. A **security group** — e.g. `AVD Lab Users`. Its object ID goes in `orchestrator.local.config.json` as `demoGroupObjectId`.
2. At least one **member user** to sign in with during the demo.

`Add-AvdLabAssignments.ps1` (not yet written) will grant that group the AVD `Desktop Virtualization User` role on the app group, plus `Storage File Data SMB Share Contributor` on the storage account. For cloud-only identities there are no NTFS ACLs anywhere in the picture — share access is governed **entirely** by Azure RBAC.

Assign the user's Windows license here too, if you have one.

---

## 8. Register MFA on the account you'll present with

Do this now, not the night before.

If Security Defaults was ever on, or any Conditional Access policy requires MFA for admins, your demo account needs a registered MFA method before it can sign in to anything. Go to [myprofile.microsoft.com](https://myprofile.microsoft.com) → **Security info** while you still have working access.

This is independent of the Kerberos exclusion. Excluding the *storage account app* from MFA does not exclude *you*.

---

## 9. Confirm you're ready

Re-run the check. You want no blockers:

```powershell
./scripts/Initialize-AvdLabPrerequisites.ps1 -SubscriptionId <guid> -TenantId <guid>
```

| Check | What you want |
| --- | --- |
| Providers | `[ok]` all four registered |
| vCPU quota | `[ok]` enough free for `sessionHostCount × vmSize` |
| Licensing | `[ok]` an eligible SKU, or a Dev/Test subscription |
| Security Defaults | `[ok]` **disabled** |
| Conditional Access | `[ok]` none, or the storage app excluded from MFA policies |
| MDM auto-enrollment | `[ok]` no scope, or you accept that hosts enroll into Intune |
| Global Administrator | `[ok]` held by the signed-in account |
| Subscription RBAC | `[ok]` Owner, or Contributor + User Access Administrator |

`Unknown` is not `Pass`. A check that could not read a policy tells you nothing about whether that policy will block you — verify it by hand rather than assuming.

Then fill in your local override file, which never gets committed:

```powershell
Copy-Item bicep/parameters/avdlab.bicepparam bicep/parameters/avdlab.local.bicepparam
Copy-Item orchestrator.config.json orchestrator.local.config.json
```

Set a globally unique `storageAccountName` (the placeholder `stavdlabfslogix` is certainly taken), a real `budgetAlertEmail`, and your `demoGroupObjectId`.

> **Note:** nothing reads those override files yet — `Deploy-AvdLab.ps1` isn't written. Until then, pass values to `New-AzResourceGroupDeployment` directly. See the README.

---

## MDM auto-enrollment: not a problem, just a surprise

If the check reports an MDM user scope, your Entra-joined session hosts will silently enroll into Intune as they join. Lab Kit doesn't ask for that and doesn't need it — Entra ID join has no Intune dependency, which is what keeps this build genuinely Intune-free.

It's a fact about your tenant, not a gap in the design. Worth knowing before you notice it on stage. Intune management proper is a Hard Mode item.

---

## What this leaves you with

A tenant and subscription where every prerequisite is satisfied, and — importantly — where you found out *today* whether Security Defaults, licensing, or quota was going to stop you, rather than at 2am the night before a talk. Those three have lead times measured in days. Everything else in this repo is code, and code fails fast.
