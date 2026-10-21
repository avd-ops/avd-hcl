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
- Applying is always you, in Cloud Shell, with a short-lived write token you create for that run.
  That is an exception to guardrail 6 and ai-brain 0016 step 3, flagged in Q5.
- The same module and the same documented settings serve a second repository of yours (section 7),
  each with its own state.

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
  repos/<second-repo>/       later, only after you name it (section 7)
  bootstrap/                 the small Azure piece the drift check needs (section 8), local state, then migrated
  scripts/app-token.py       mints a read-only installation token from a Key Vault-signed JWT
  conventions.md             the settings table in section 5, with where each one comes from
```

- `github/` never shares state, variables or providers with `environments/`. The kit's roots
  never reference `github/`, and `github/` never reads the kit's state.
- Provider: `integrations/github`, pinned to the release current at build time (`~> 6.x`), and
  Terraform pinned to the version CI uses once PR #10 merges (1.16.6; `main` has 1.11.4 today). Nothing in `github/` uses a feature
  OpenTofu lacks, so the folder also runs under `tofu` (section 10).
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
| Description | "Native Azure Virtual Desktop with Terraform, Packer and Vault" | proposed here: today's text describes the removed lab kit |

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

## 7. Two repositories, one set of settings

- **One module, one variable set.** `github/modules/repo-settings` carries the conventions in
  section 5 as defaults. Each repository is a root under `github/repos/` that passes only what
  must differ: its name, its required checks (each repo runs different CI), its extra labels, and
  whether it is public. `conventions.md` lists each default with its source, so a change to a
  convention is one PR here, and the per-repo differences are visible in two short files.
- **Which repository is the second one?** Not stated, so not guessed. The likely candidates and how
  they differ from avd-hcl today, for you to decide:

| | avd-hcl | nerdio-hcl | ai-brain |
|---|---|---|---|
| Visibility | private | public | public |
| `main` protected | no | no (its own `modules/github-repo` defines a ruleset, but none shows on `main`) | not readable from this session |
| Auto-merge | none | none | `kb-auto-merge` on, paths `docs/**`, `README.md`, `llms.txt` |
| Required checks it would get | `Terraform`, `Parameter schema`, `Guard`, `gitleaks` | its `validate` jobs and `gitleaks` (names to confirm) | `auto-merge`, `kb-validate`, `gitleaks` (`secrets`), `kb-capture` |
| Secret scanning, push protection | not available while private | available | available |
| Extra labels | none | `kb-*` labels its own module creates | `kb-*` labels |
| CODEOWNERS | none | none | yes (directives file) |

- Flagged for you: **auto-merge** (on in ai-brain, off here), **secret scanning** (public only),
  **required checks** (always per repo), and nerdio-hcl's **unenforced ruleset**. If the second
  repo is nerdio-hcl, its own `modules/github-repo` (applied by its bootstrap) would also manage
  labels, the workflow token and a ruleset on the same repo: two owners of one setting fight, so
  one of them has to step back (Q3). Stepping back means changing nerdio-hcl's deploy-pipeline
  bootstrap root (`environments/example/00-pipeline/main.tf` applies that module), and its
  `actions_can_open_pull_requests = true` default (needed by its `kb-feedback` workflow) differs
  from this spec's "Actions can't approve PRs".
- A public repository never names avd-hcl, so the second repository's root lives here, in
  `github/repos/<name>/`, not in that repository.

## 8. Credentials (no long-lived token anywhere, per 0016)

**Drift check (CI, read-only): a GitHub App whose private key never leaves Azure Key Vault.**

- Why an App at all: the workflow's own `GITHUB_TOKEN` has no `administration` scope, so it can't
  read rulesets' enforcement details, security settings or workflow permissions.
- A private GitHub App, "avd-hcl settings reader", installed on this repository only (and the
  second repository later). Repository permissions: **Administration: read** (merge settings,
  rulesets, security settings, Dependabot, workflow permissions), **Issues: read** (labels),
  **Metadata: read** (required). Nothing else: no write permission, no webhook.
- Its private key is imported into a Key Vault as a **non-exportable key with only the `sign`
  operation**, then the downloaded file is deleted. Nobody can read the key back, including the
  workflow; it can only ask Key Vault to sign a 9-minute JWT, which GitHub exchanges for a
  one-hour installation token **scoped to this repository and those read permissions**. The token
  is masked in logs and passed to Terraform as `GITHUB_TOKEN` for that one job. This is the same
  pattern nerdio-hcl's setup chat uses for its GitHub App (`assistant/pipeline.py`), reused with
  credit.
- The workflow reaches Key Vault through OIDC: a user-assigned managed identity with one federated
  credential for the subject `repo:nickprignano/avd-hcl:ref:refs/heads/main`, so only a run of
  `main`'s workflow code gets it; a dispatch from any other branch fails to sign in. It holds
  **Key Vault Crypto User** on that one key and **Storage Blob Data Reader** on the state
  container. Its client, tenant and subscription IDs are repository *variables* (`vars.*`), not
  secrets, and are never in the repo.
- No GitHub environment is needed: the subject pins `main`, which is what an environment limited
  to `main` would do, and it works without GitHub Pro on a private repo. There is no reviewer:
  one would hold every scheduled run, and these credentials can't change settings. 0016 asks for a
  reviewer on *deploy* credentials only (Q4).

**Apply (you, in Cloud Shell): a fine-grained token you create for the run and revoke after.**

- Fine-grained personal access token, **only this repository**, expiry the next day, permissions
  **Administration: read and write**, **Issues: read and write**, **Metadata: read**. You type it
  with `read -rs GITHUB_TOKEN` in Cloud Shell, so it is never in a file, history, chat or the
  repo; you revoke it on GitHub after the apply.
- This is an **exception, flagged for you (Q5)**: guardrail 6 says applies run after a named
  reviewer approves them, and 0016 step 3 puts an unavoidable deploy token in an environment
  secret with a reviewer and a vault entry. Here the reviewer and the person applying are both
  you, there is no stored token to put in a vault, and "a session never applies" is a rule, not a
  check (0016 step 6). Alternatives: (a) an `apply` workflow in an environment with you as
  required reviewer (needs Pro while private, and a write credential that CI can reach, which this
  spec otherwise avoids); (b) a second "settings writer" App whose key sits in Key Vault, signable
  only by your own Entra account: keyless, no token to create each time, more setup. Q11 covers
  0016's planned separate GitHub account for sessions, which would turn the rule into a check.

**Bootstrap (`github/bootstrap/`, Azure, needs your go):** one resource group with a Key Vault
(RBAC, purge protection), a storage account and container for the state, the managed identity,
its federated credential and two role assignments. Estimate, to confirm against the retail price
meters before the go: under **$0.20 a month** (Key Vault standard software-key operations at a few
signs a day, one small blob, no compute). It is a standing resource on purpose, so it is recorded
as a recurring cost, not torn down.

**What you click (nothing else can do these):**

1. Create the "settings reader" GitHub App (settings: no webhook, the three read permissions,
   only on this account), install it on this repository, download one private key. A manifest
   link, like nerdio-hcl's one-click setup page, can pre-fill this.
2. In Cloud Shell: upload the key file, move it to `/tmp` (local to the session, not the
   `clouddrive` file share, where deleting doesn't overwrite and snapshots can keep a copy),
   import it into Key Vault as non-exportable with only the `sign` operation, delete it, and
   delete the download on your device. GitHub mints the key, so it is briefly on two devices:
   if either is lost, rotate the App key (0016 step 9). This is the weakest step in the chain.
3. In the repository's settings: the three ID variables (a script can set them with your `gh`
   sign-in instead, your choice).
4. For each apply: create the fine-grained token above, run the apply block, revoke the token.

Claude's GitHub tools can't read or change rulesets or most repository settings, and no session
holds an admin credential, so every step that changes GitHub is one of the above.

## 9. Drift workflow

`.github/workflows/github-drift.yml`:

- Triggers: `schedule` (daily, off the hour) and `workflow_dispatch`; both jobs also check
  `github.ref == 'refs/heads/main'`, and the OIDC subject refuses any other ref anyway.
- **Job `plan`**, permissions `contents: read`, `id-token: write` only: checkout; setup Terraform
  (pinned); Azure sign-in by OIDC; mint the read-only App token; `terraform init` with backend
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
- What can write: the `plan` job can read state and sign one JWT, and its App token can only read.
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
| **Terraform + `integrations/github`** | Yes: plan shows drift, import of existing settings, `terraform test` offline, same tool and CI pin as the rest of this repo | Terraform is **BSL 1.1** (source-available, not OSI open source); the GitHub provider is MIT | **Pick for this repo**: decision 0001 already chose the HashiCorp stack, and a second tool in one repo is worse than one |
| **OpenTofu** | Yes, the same provider and HCL; adds client-side state encryption | **MPL-2.0**, Linux Foundation | Runner-up. The folder stays OpenTofu-compatible so switching is a binary change. Whether the whole repo should move is a repo-wide question decision 0001 didn't weigh (Q1) |
| **Safe Settings** (GitHub's Probot app) | Partly: settings from YAML in an `admin` repo, `nop` dry-run on PRs, rulesets supported | ISC | No: built for organizations (an `admin` repo in the org), needs hosting, and its normal mode **reverts** drift with a standing write credential, which this spec rules out |
| **Settings app** (`.github/settings.yml`, Probot) | Applies on push, no drift report, limited ruleset support | ISC | No: applies automatically |
| **nerdio-hcl `modules/github-repo`** (yours, Apache-2.0) | Labels, workflow token, ruleset on one branch | Yes | Reused as the starting point, with credit; this module adds merge settings, security, topics and required checks |
| **Build our own** (snapshot with `gh api` and diff, like avd-landing-zone's snapshot diff) | Drift report only, no apply | n/a | No: you asked for the provider, and it would re-implement import and plan |

Under the family's build-or-adopt rule, Terraform is the pick here only because this repository is
already Terraform; on licensing alone OpenTofu wins.

## 11. Order of work, each step on your word

1. **This spec** (PR, docs only). You approve or change it.
2. **Code PR, offline:** `github/` module and root, import blocks, tests, the drift workflow
   (inert until step 4), `conventions.md`, CI. No credential, nothing applied.
3. **First plan, read-only:** you create a read-only fine-grained token (same as section 8's apply
   token but read permissions only), run one Cloud Shell block that runs `terraform plan` with
   local state, and paste the plan's text here. Nothing changes.
4. **Bootstrap**, after a written estimate and your go: the Azure pieces, the App, the key import,
   the repository variables. The first drift run is started by hand and should report the same plan as
   step 3.
5. **Apply**, on your go and only after PR #10 has merged (the required check names come from
   it), from Cloud Shell with the write token; the drift run after it must be clean. Then the follow-up PR adding import blocks for the new objects.
6. **Second repository**, once you name it (Q3).

## 12. Open questions for you

Collected in the PR and the thread reply; numbered here so answers can refer to them.

- **Q1.** Terraform (BSL) or OpenTofu (MPL-2.0) for this folder, and is the license question worth
  a repo-wide decision record?
- **Q2.** Is your account on GitHub Pro? Rulesets on a private personal repo need it (the drift
  check no longer does). Without Pro, the ruleset only takes effect once the repo is public.
- **Q3.** Which is the second repository, and if it's nerdio-hcl, does its own
  `modules/github-repo` step back for that repo?
- **Q4.** OK that the read-only drift check runs with no reviewer, pinned to `main` by its OIDC
  subject instead of a GitHub environment?
- **Q5.** Apply with a one-day fine-grained token you type in Cloud Shell (simple; an exception to
  guardrail 6 and 0016 step 3), a reviewer-gated `apply` workflow, or a second Key Vault-held
  "writer" App (keyless, more setup)?
- **Q6.** Key Vault for the reader App's key (recommended, about $0.20 a month, needs a go), or the
  key as a `github-drift` environment secret ($0, but a long-lived key in Actions secrets, which
  you ruled out)?
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
  runs?), and is the standing cost of about $0.20 a month recorded alongside the sandbox spend
  records?

Red-teamed with Fable on 2026-10-21: 17 findings, all taken. Changed as a result: required check
names and the Terraform pin follow PR #10, and the ruleset applies only after it; the full list of
`github_repository` arguments whose provider defaults differ (Issues off by default); ruleset
ordering diffs handled before apply; backend uses Entra auth; the plan and issue steps are
separate jobs with the issue step always running, deduplicated, and honest about the labels it
could write; OIDC pinned to `main` by subject, so no environment and no Pro dependency for the
check; the key hand-off avoids the Cloud Shell file share; the apply token is flagged as an
exception to guardrail 6 and 0016; nerdio-hcl's conflict named precisely; Q9 to Q12 added.
