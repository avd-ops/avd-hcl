# Contributing to AVD Lab Kit

## Secrets & leak prevention

This repo is private today and goes public at the `v1.0.0` release. Treat every commit as permanent and world-readable from now anyway: flipping visibility exposes the entire history at once, so a real value committed today is a leak on release day, not a mistake you get to quietly delete beforehand.

**Tracked files hold placeholders only.** `bicep/parameters/avdlab.bicepparam` and `orchestrator.config.json` carry `<YOUR_SUBSCRIPTION_ID>`-style tokens and nothing else. Your real subscription ID, tenant ID, demo group object ID, and budget alert email go in a local override that git never sees:

| Tracked (placeholders) | Local override (gitignored) |
| --- | --- |
| `bicep/parameters/avdlab.bicepparam` | `bicep/parameters/avdlab.local.bicepparam` |
| `orchestrator.config.json` | `orchestrator.local.config.json` |

Both override patterns are in `.gitignore` and were there before the first commit. Don't remove them, and don't `git add -f` past them.

**No hardcoded local admin passwords, ever.** The orchestrator generates a random password at runtime for session host provisioning and discards it afterward; Entra ID join means nothing needs it long-term. A `@secure()` Bicep parameter with a default value is the same mistake wearing a hat — the Pester suite fails the build if it finds one.

### Enable the pre-commit hook

The hook is the actual control. CI and GitHub push protection are backstops that catch what it misses.

```sh
winget install gitleaks          # or: https://github.com/gitleaks/gitleaks/releases
git config core.hooksPath .githooks
```

It fails closed: if `gitleaks` isn't on your PATH, the commit is blocked rather than passing unscanned. That's deliberate — a scanner that silently no-ops reads as protection you don't have.

### If a real value does get committed

Deleting the line in a later commit does **not** remove it from history.

1. **Rotate or invalidate the credential immediately.** Assume it's compromised the moment it's committed, whether or not it was ever pushed.
2. **Scrub it from history** with `git filter-repo` or BFG Repo-Cleaner before the repo is public.
3. Only then continue.

## Scope discipline: Easy Mode vs. Hard Mode

v1 is **Easy Mode** — Entra ID join, no AD DS, no on-prem dependency, one resource group, one-command teardown. It is deliberately small enough to read in one sitting and fork without standing up a domain controller first.

If a change requires a domain controller, a VNet peering, a Private Link endpoint, a custom image, Intune, a GPU, a second region, or Azure Government endpoints — it's **Hard Mode**, and it belongs in the roadmap rather than in a v1 PR. That isn't a rejection of the idea; it's what keeps Easy Mode easy. Open an issue describing which tier (v2–v5) it fits.

## Conventions

- **Naming:** `<resourceType>-avdlab-<qualifier>` across both the Bicep and PowerShell layers.
- **Bicep** for anything that's a clean ARM resource. **PowerShell** only for what genuinely isn't — Graph calls, Azure AD Kerberos enablement, live-demo narration.
- One `New-AzResourceGroupDeployment` call per module, sequenced by the orchestrator. Not one monolithic `main.bicep` — the phase-by-phase narration is a feature.
- Every module must pass `az bicep build` and the Pester suite before merge.

## Before you open a PR

```sh
az bicep build --file bicep/modules/<module>.bicep --stdout > /dev/null
Invoke-Pester ./tests
```

CI runs `az bicep build` on every module, the Pester suite, and a `gitleaks` history scan. Check that CI is green before merging — as a solo-committer repo on the Free tier, that self-gate stands in for enforced branch protection.
