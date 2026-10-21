---
title: "GitHub settings as code"
summary: "Spec: this repository's GitHub settings declared with the Terraform GitHub provider in github/, imported first, checked for drift on a schedule, never applied by CI"
topic: github
status: proposed
last_reviewed: 2026-10-21
---

# GitHub settings as code

**Status: proposed, nothing applied.** This is a spec for the owner to approve. No GitHub setting,
Azure resource or credential changes until the owner says yes to each step in section 11.

## 1. What changes for you

- This repository's GitHub settings (merge options, the ruleset on `main`, required checks,
  labels, security settings, topics) live in `github/` as Terraform, beside the kit but with its
  own state and its own credentials.
- The first `terraform plan` imports what is set today. On a repository that already matches, it
  shows zero changes; where it differs, it shows exactly what would change. You see that plan
  before anything is applied.
- A scheduled workflow runs `terraform plan` every day with **read-only** GitHub credentials and
  opens (or updates) one `drift` issue when settings no longer match the code, or when the check
  itself breaks. It has no apply step, and the plan job's credentials can't change settings even
  if someone added one. The issue job's own token can write issues and labels, and nothing else
  (section 9).
- Applying is always you, in Cloud Shell, signed in to Azure as yourself: Key Vault signs for a
  short-lived write token with a key only your account may use (section 8). Before that key
  exists, the first apply uses a fine-grained token you create for the run and revoke after.
- The conventions are written down once (`github/conventions.md`) so your other HCL repository,
  nerdio-hcl, can be kept the same from its own project (section 7).

## 2. What exists today (read 2026-10-21, read-only)

| Setting | Today | Source |
|---|---|---|
| Visibility | private | repository API |
| `main` protection | none (no branch protection or ruleset shows on `main`) | branches API |
| Labels | no `no-kb` label | labels API |
| Topics | none | repository API |
| Description | "Native AVD Lab Deployment Framework" (from the removed lab kit) | repository API |
| Wiki, Discussions | off | repository API |
| Projects, forking | on | repository API |
| Merge options, auto-merge, delete branch on merge, Dependabot, workflow token default | **not visible** with the tools this session has; the first plan shows them | |
| Issues | on (the drift issue needs it) | repository API |
| CI checks on every PR | on `main` today: `Terraform fmt`, `Guard`, `gitleaks`; PR #10 renames the first to `Terraform` and adds `Parameter schema` | `.github/workflows/ci.yml` on `main` and on PR #10 |
| Terraform in CI | 1.11.4 on `main`, 1.16.6 on PR #10 | `.github/workflows/ci.yml` |

## 3. Layout

```
github/
  modules/repo-settings/     one module: every setting in section 5, with the conventions as defaults
    main.tf variables.tf outputs.tf versions.tf
    tests/repo_settings.tftest.hcl   offline, mock provider
  repos/avd-hcl/             the root for this repository (its own state)
    main.tf                  module call with this repo's few overrides
    imports.tf               one import block per managed object (section 6)
    backend.tf               azurerm backend, key github/avd-hcl.tfstate, use_azuread_auth and
                             use_oidc on (Reader can't list storage keys); values from -backend-config
    versions.tf              integrations/github pinned; provider "github" { owner = "nickprignano" },
                             token from GITHUB_TOKEN in the environment
  bootstrap/                 the small Azure piece (Key Vault, state container, identity; section 8)
  scripts/app-token.py       mints an installation token from a JWT signed by Key Vault
  conventions.md             the settings table in section 5, with where each one comes from
```

- **One owner per setting.** GitHub environments (the kit's `<env>-plan` and `<env>-apply`, their
  branch policies, reviewers and environment secrets) belong to the kit's deploy pipeline
  (`environments/example/00-pipeline`, port plan phase 2), never to `github/`. `github/` owns
  everything else in section 4, and the pipeline module touches none of it. Required reviewers on
  environments in a private repository need GitHub Enterprise (environments and branch policies
  need Pro), which matters for that pipeline while this repo is private.
- `github/` never shares state, variables or providers with `environments/`. The kit's roots
  never reference `github/`, and `github/` never reads the kit's state.
- Provider: `integrations/github`, pinned to the release current at build time (`~> 6.x`), and
  Terraform pinned to the version CI uses once PR #10 merges (1.16.6; `main` has 1.11.4 today). Nothing in `github/` uses a feature
  OpenTofu lacks, but the tool is Terraform Community Edition (decision 0004, section 10).
- `prevent_destroy` on the repository resource and `archive_on_destroy = true`: a
  `github_repository` destroy deletes the repository, so neither a typo nor `terraform destroy`
  can do that. Retiring this setup uses `removed { lifecycle { destroy = false } }` blocks, which
  stop managing a setting without changing it.

## 4. Resources

| Setting | Resource | Notes |
|---|---|---|
| Merge options, auto-merge, delete branch on merge, issues/wiki/projects/discussions, topics, description, Dependabot alerts, secret scanning and push protection | `github_repository` | Every argument with a non-computed default is set explicitly, so a provider default can't silently change a setting. Several defaults differ from GitHub's: `has_issues` defaults to **false** in the provider, which would turn Issues off. The full list (`has_issues`, `has_wiki`, `has_projects`, `has_discussions`, `allow_merge_commit`, `allow_squash_merge`, `allow_rebase_merge`, `allow_auto_merge`, `allow_update_branch`, `delete_branch_on_merge`, `merge_commit_title`, `merge_commit_message`, `web_commit_signoff_required`, `vulnerability_alerts`, `homepage_url`, `archived`, `topics`, `description`) is asserted by the module test |
| Ruleset on `main` | `github_repository_ruleset` | Chosen over classic branch protection: one resource, bypass list, required checks pinned to the GitHub Actions app. This resource has a history of ordering diffs (bypass actors, required checks, an empty `exclude`); any that appear in the step-3 plan get a reasoned `ignore_changes` before apply, not a daily drift issue |
| Labels | `github_issue_label`, one per label | Manages only the listed labels; other labels are left alone (not `github_issue_labels`, which would delete unlisted ones) |
| Dependabot security updates | `github_repository_dependabot_security_updates` | |
| Default workflow token read-only, Actions can't approve PRs | `github_workflow_repository_permissions` | Same as nerdio-hcl's `modules/github-repo` |
| Dependabot version updates | `.github/dependabot.yml` (a file, not a setting) | Proposed for `github-actions` and `terraform`, weekly; your call (Q7) |

## 5. The settings, and where each comes from

"0014" and "0016" are ai-brain's decisions: [0014](https://github.com/nickprignano/ai-brain/blob/main/docs/knowledge/decisions/0014-family-format-auto-merge-low-risk-prs.md)
(GitHub work conventions, status *proposed* in ai-brain) and
[0016](https://github.com/nickprignano/ai-brain/blob/main/docs/knowledge/decisions/0016-secrets-handling.md)
(secrets, *accepted*). "0011" and "0012" are ai-brain's knowledge-capture and handoff decisions.
Anything marked **proposed here** has no source in those decisions and is for you to confirm.

| Setting | Value for avd-hcl | Source |
|---|---|---|
| Merge commits | allowed | 0014 ("it uses merge commits") |
| Squash, rebase merges | off | proposed here: one merge method, matching 0014 |
| Allow auto-merge | **off** until a `kb-auto-merge` workflow is installed here | 0014 section 3: it's turned on only with the workflow, and only for docs paths in an infrastructure repo. The module's `kb_auto_merge` switch turns on "Allow auto-merge" and adds the `auto-merge` required check together, as 0014 requires |
| Delete head branch on merge | on | proposed here (stray `claude/*` branches pile up today) |
| Ruleset `main`: require a pull request | yes, 0 approvals | 0014 ("no required review, because the owner can't approve their own PRs"); 0016 step 6 backstop |
| Ruleset: block force push and deletion | yes | 0016 step 6 backstop; nerdio-hcl's module does the same |
| Ruleset: required checks | `Terraform`, `Parameter schema`, `Guard`, `gitleaks` (the job display names after PR #10; the ruleset is applied only after #10 merges) | 0014 section 3: require the checks the repo actually runs on every PR, never one that doesn't report. A renamed CI job is a settings change: the same PR updates this list |
| Ruleset: require branch up to date | off | proposed here: avoids re-running CI on every merge for a one-person repo |
| Ruleset bypass | repository admin role, pull requests only | 0014 section 3 |
| Ruleset enforcement | `active` | needs GitHub Pro while the repo is private (Q2) |
| Labels | `no-kb`, `no-auto-merge`, `handoff`, `handoff-proposed`, `drift` | 0011 (`no-kb`), 0014 (`no-auto-merge`), 0012 (`handoff`, `handoff-proposed`); `drift` is this spec's issue label |
| Dependabot alerts and security updates | on | proposed here (free on every plan) |
| Secret scanning, push protection | on **only when public**; while private, gitleaks (pre-commit and CI) is the control | 0016 step 11. GitHub doesn't offer secret scanning on private repos owned by a personal account, and setting it there fails, so the module sets it from the visibility |
| Default workflow token | read-only; Actions can't approve PRs | proposed here, as nerdio-hcl's module does; every workflow here already declares its own permissions |
| Issues | on | today's value; the provider's default is off |
| Wiki, Discussions | off | today's values |
| Projects | off | proposed here (the personal board is a user-level project, not a repo tab) |
| Forking | left as is | private repos of a personal account can't change it; the argument is omitted |
| Topics | `azure-virtual-desktop`, `terraform`, `packer`, `azure`, `infrastructure-as-code` | proposed here (Q8) |
| Description | "Native Azure Virtual Desktop with Terraform and Packer" | proposed here: today's text describes the removed lab kit |

## 6. Import first, then plan

- `imports.tf` holds an `import` block for each object that exists today: the repository, the
  workflow permissions, Dependabot security updates. Objects that don't exist yet (the ruleset,
  the five labels) have no import block, so the first plan shows them as **creates**. After the
  first apply, a follow-up PR adds their import blocks, so a fresh state can always be rebuilt
  from GitHub.
- Ruleset IDs are not written into the repo: a later import uses the ruleset's ID passed as a
  variable from the plan output, or the state that already holds it.
- The first plan is expected to show: `import` for the existing objects, `create` for the ruleset
  and labels, and in-place `update` for any setting in section 5 that differs today (at least the
  description, topics and Projects). Anything else in that plan is a drift we didn't know about
  and is discussed before apply.
- Offline guard: `terraform test` with `mock_provider "github"` checks the module's outputs (each
  argument in section 4's list set, Issues on, secret scanning off for a private repo,
  `prevent_destroy` present, required checks list non-empty, `kb_auto_merge` adds both settings).
  It joins the existing Terraform CI job.
- To check on the first plan, not assumed: whether the API rejects squash commit message
  settings while squash merges are off (if so, the module leaves them unset).

## 7. Same settings as nerdio-hcl

The second repository is nerdio-hcl (owner, 2026-10-21). It is handled in its own project, so this
spec manages avd-hcl only and nothing here reads or writes nerdio-hcl.

- **The documented variable set is the shared part.** `github/conventions.md` lists every setting
  in section 5 with its source, and the module carries them as defaults. nerdio-hcl's project can
  match them with its own `modules/github-repo` (which nerdio-hcl's bootstrap already applies to
  that repo) or by reusing this module; that choice is theirs.
- **Differences seen today, for that project to decide** (read-only, 2026-10-21): nerdio-hcl is
  public, so secret scanning and push protection are available there and not here; its own module
  defines a ruleset, but none shows on its `main`; its `actions_can_open_pull_requests = true`
  (its `kb-feedback` workflow needs it) differs from section 5's "Actions can't approve PRs"; its
  required checks are its own CI job names.
- One repository's settings never have two owners: whatever manages nerdio-hcl's settings stays
  in that repository's project.

## 8. Credentials (no long-lived token anywhere, per 0016; Key Vault holds the keys)

No Vault server (decision 0004). Both GitHub App keys are **non-exportable Azure Key Vault keys
with only the `sign` operation**: they can sign, but nobody can read them back, so no credential
exists outside Key Vault and nobody, Claude included, ever holds one. This is the pattern
nerdio-hcl's setup chat uses for its GitHub App (`assistant/pipeline.py`), reused with credit.

**Why an App at all:** the workflow's own `GITHUB_TOKEN` has no `administration` scope, so it
can't read rulesets' details, security settings or workflow permissions.

**Two private GitHub Apps, installed on this repository only, no webhook:**

| App | Repository permissions | Who may ask Key Vault to sign with its key |
|---|---|---|
| settings reader | **Administration: read**, **Issues: read** (labels), **Metadata: read** | the drift workflow's managed identity, from `main` only |
| settings writer | **Administration: read and write**, **Issues: read and write**, **Metadata: read** | your own Entra account, from Cloud Shell |

**How a run gets a token:**

1. It signs in to Azure: the drift workflow by GitHub OIDC as a user-assigned managed identity
   whose one federated credential has the subject `repo:nickprignano/avd-hcl:ref:refs/heads/main`
   (a dispatch from any other branch is refused, and no GitHub environment or Pro plan is
   needed); you with your own account in Cloud Shell.
2. It asks Key Vault to sign a 9-minute App JWT (RS256). Role assignments are **per key**: the
   managed identity has **Key Vault Crypto User** on the reader key only, you on the writer key
   only. The identity also has **Storage Blob Data Reader** on the state container and nothing
   else. Its client, tenant and subscription IDs are repository variables (`vars.*`), not
   secrets, and never in the repo.
3. GitHub exchanges the JWT for a one-hour installation token **scoped to this repository and that
   App's permissions**. It is masked in logs and passed to Terraform as `GITHUB_TOKEN` for that
   one process.

**Applies:** always you, from Cloud Shell, with the writer App: keyless, no token to create or
revoke. Guardrail 6's reviewer and the person applying are the same person, and "a session never
applies" holds because no session can sign in to Azure as you. Q11 still covers 0016's planned
separate GitHub account for sessions. Before the writer key exists (the first apply, section 11
step 4), a one-day fine-grained token with the writer App's permissions, typed with
`read -rs GITHUB_TOKEN` and revoked after.

**Bootstrap (`github/bootstrap/`, Azure, needs your go):** one resource group with a Key Vault
(RBAC, purge protection), a storage account and container for the state, the managed identity,
its federated credential and three role assignments. Estimate, to confirm against the retail price
meters before the go: under **$0.20 a month** (Key Vault standard software-key operations at a few
signs a day, one small blob, no compute). It is a standing resource on purpose, so it is recorded
as a recurring cost, not torn down.

**What you click (nothing else can do these):**

1. Create the two GitHub Apps (a manifest link can pre-fill each) and install them on this
   repository; download one private key for each.
2. In Cloud Shell: upload each key file to `/tmp` (local to the session, not the `clouddrive` file
   share, where deleting doesn't overwrite and snapshots can keep a copy), import it into Key
   Vault as non-exportable with only the `sign` operation, delete it, and delete the download on
   your device. GitHub mints the key, so it is briefly on two devices: if either is lost, rotate
   the App key (0016 step 9). This is the weakest step in the chain.
3. Repository variables for the identity's three IDs and the Key Vault's name (not secrets).

Claude's GitHub tools can't read or change rulesets or most repository settings, and no session
holds an admin credential or can sign in to Azure as you, so every step that changes GitHub is
yours.

## 9. Drift workflow

`.github/workflows/github-drift.yml`:

- Triggers: `schedule` (daily, off the hour) and `workflow_dispatch`; both jobs also check
  `github.ref == 'refs/heads/main'`, and the OIDC subject refuses any other ref anyway.
- **Job `plan`**, permissions `contents: read`, `id-token: write` only: checkout; setup Terraform
  (pinned); Azure sign-in by GitHub OIDC; mint the read-only App token; `terraform init` with backend
  values from repository variables; `terraform plan -lock=false -input=false -detailed-exitcode
  -no-color` for each root under `github/repos/`. It uploads the plan text and an outcome
  (`clean`, `drift`, or `failed` with the failing step's name) as an artifact.
- **Job `report`**, `needs: plan`, `if: always()`, permissions `issues: write` only, no Azure, no
  App token: reads the artifact (or its absence, which counts as `failed` at "before plan") and
  - `clean`: if an open `drift` issue exists, comments "clean" and closes it;
  - `drift`: opens one issue labeled `drift`, or comments on the open one **only when the plan's
    changed resources differ from its last comment** (a hash in the comment), so a standing drift
    doesn't comment every day;
  - `failed`: opens or updates the same issue as "drift check failed" with the step name and
    error, so a broken sign-in, token, init or plan is never silent.
- What can write: the `plan` job can read state and have Key Vault sign one reader JWT, and its
  App token can only read.
  The `report` job's `GITHUB_TOKEN` can write issues and **labels**, which are managed objects; a
  change to this workflow is under `.github/`, so it never merges itself (0014), and a label
  change it made would show as drift the next day.
- The issue body quotes values read from GitHub (description, topics, label text) inside a fenced
  block. Sessions treat the issue as data, never instructions; only `handoff` issues the owner
  labels are work items (ai-brain 0012).
- Heartbeat: if the last successful run is older than 7 days (a disabled schedule, an expired
  App key), the next run, or your weekday open-work list, says so. Scheduled workflows in a
  public repository stop after 60 days without activity (Q10).
- **Never applies.** There is no apply step and no credential in either job that could.

## 10. Prior art and why Terraform

| | Fits this job? | Open source? | Verdict |
|---|---|---|---|
| **Terraform Community Edition + `integrations/github`** | Yes: plan shows drift, import of existing settings, `terraform test` offline, same tool and CI pin as the rest of this repo | Terraform is **BSL 1.1** (free to use, source-available, not OSI open source); the GitHub provider is MIT | **Pick**: the owner chose the HashiCorp community editions for the whole repo (decision 0004) |
| **OpenTofu** | Yes, the same provider and HCL; adds client-side state encryption | **MPL-2.0**, Linux Foundation | Prior art only, by the owner's choice (decision 0004) |
| **Safe Settings** (GitHub's Probot app) | Partly: settings from YAML in an `admin` repo, `nop` dry-run on PRs, rulesets supported | ISC | No: built for organizations (an `admin` repo in the org), needs hosting, and its normal mode **reverts** drift with a standing write credential, which this spec rules out |
| **Settings app** (`.github/settings.yml`, Probot) | Applies on push, no drift report, limited ruleset support | ISC | No: applies automatically |
| **nerdio-hcl `modules/github-repo`** (yours, Apache-2.0) | Labels, workflow token, ruleset on one branch | Yes | Reused as the starting point, with credit; this module adds merge settings, security, topics and required checks |
| **Build our own** (snapshot with `gh api` and diff, like avd-landing-zone's snapshot diff) | Drift report only, no apply | n/a | No: you asked for the provider, and it would re-implement import and plan |

This repository is outside the avd-ops family, and its owner chose the HashiCorp community
editions knowing they are source-available (decision 0004); OpenTofu and OpenBao stay as prior art.

## 11. Order of work, each step on your word

1. **This spec** (PR, docs only). You approve or change it.
2. **Code PR, offline:** `github/` module and root, import blocks, tests, the drift workflow
   (inert until step 5), `conventions.md`, CI. No credential, nothing applied.
3. **First plan, read-only:** you create a read-only fine-grained token (the permissions of the
   reader App), run one Cloud Shell block that runs `terraform plan` with local state, and paste
   the plan's text here. Nothing changes.
4. **First apply**, on your go and only after PR #10 has merged (the required check names come
   from it), from Cloud Shell with a one-day fine-grained write token, revoked after. Local
   state moves to the state container afterwards (step 5). Then the follow-up PR adding import
   blocks for the new objects.
5. **Bootstrap and the drift check**, after a written estimate and your go: the Key Vault, state
   container and identity, both Apps and their keys, the repository variables. The first drift
   run is started by hand and must be clean. From then on, applies use the writer App and no
   token is created by hand.

## 12. Open questions for you

Collected in the PR and the thread reply; numbered here so answers can refer to them.

- **Q1.** Answered: Terraform and Packer community editions, no Vault (decision 0004).
- **Q2.** Is your account on GitHub Pro? Rulesets on a private personal repo need it (the drift
  check no longer does). Without Pro, the ruleset only takes effect once the repo is public.
- **Q3.** Answered: the second repository is nerdio-hcl, handled in its own project (section 7).
- **Q4.** OK that the read-only drift check runs with no reviewer, pinned to `main` by its OIDC
  subject instead of a GitHub environment?
- **Q5.** Answered: a "settings writer" App whose key Key Vault holds, signable only by your
  account; a fine-grained token only for the first apply.
- **Q6.** Answered: Azure Key Vault holds both App keys; no Vault server (decision 0004).
- **Q7.** Delete branches on merge, squash and rebase off, Projects off, Dependabot version updates
  file: yes to each?
- **Q8.** Topics and the new description as proposed?
- **Q9.** Drop the state backend? With an import block for every managed object, a plan against
  an empty local state shows the same drift (imports plus updates), and the storage account goes
  away. The cost: the ruleset's numeric ID is written into the import block (a GitHub ID, not a
  tenant or subscription ID, but still an ID), and whether `import.id` may come from a variable in
  the pinned Terraform needs checking first.
- **Q10.** When the repository goes public: turn on secret scanning and push protection in the
  same PR as the visibility change, keep the reader App installed, and accept the 60-day rule for
  scheduled workflows?
- **Q11.** Does this wait for 0016 step 6's separate GitHub account for sessions (a collaborator
  without admin, which would make "a session never applies" a technical gate), or go ahead
  without it?
- **Q12.** Which Azure subscription holds the bootstrap (your personal sandbox, as with the kit's
  runs?), and is its standing cost of under $0.20 a month recorded alongside the sandbox spend
  records?
- **Q13.** Answered: no Vault server (decision 0004).

Red-teamed with Fable on 2026-10-21: 17 findings, all taken. Changed as a result: required check
names and the Terraform pin follow PR #10, and the ruleset applies only after it; the full list of
`github_repository` arguments whose provider defaults differ (Issues off by default); ruleset
ordering diffs handled before apply; backend uses Entra auth; the plan and issue steps are
separate jobs with the issue step always running, deduplicated, and honest about the labels it
could write; OIDC pinned to `main` by subject, so no environment and no Pro dependency for the
check; the key hand-off avoids the Cloud Shell file share; the apply token is flagged as an
exception to guardrail 6 and 0016; nerdio-hcl's conflict named precisely; Q9 to Q12 added. Later the same day the owner named
nerdio-hcl as the second repository and moved it to its own project, so section 7 shrank to the
shared settings table.

Updated 2026-10-21 evening: the owner chose the Terraform and Packer community editions and,
after weighing a Vault server's cost, no Vault (decision 0004). Section 8 keeps both App keys in
Azure Key Vault and adds a writer App, so applies after the first are keyless.
