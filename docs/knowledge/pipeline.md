---
title: "Deploy pipeline: the gate and who can do what"
summary: "How plans and applies run from GitHub Actions with no Azure secret, what each identity may do, and what GitHub's plans allow in a private repository"
topic: pipeline
status: built-offline
last_reviewed: 2026-10-22
---

# Deploy pipeline: the gate and who can do what

Adapted from nerdio-hcl's deploy pipeline (Apache-2.0, commit `75f59bc`; see
[CREDITS.md](../../CREDITS.md)). Built and tested offline only; it has not run against Azure or
GitHub yet (that needs a written estimate and the owner's exact go).

## How a change goes out

1. Once, from Cloud Shell: `python3 scripts/schema/answers.py init`, then
   `./scripts/pipeline/bootstrap.sh`. It plans `environments/example/00-pipeline`, applies after
   you type yes, moves that stage's state into the storage it just made, and publishes your
   answers (`answers/<env>.json`, versioned).
2. Actions > Deploy > Run workflow. The **plan** job signs in as the plan identity, renders the
   answers into `setup.auto.tfvars.json` with `answers.py render`, plans, and saves the plan with
   its SHA-256 in the `plans` container. The job summary lists every change, with IDs masked.
3. With "apply" ticked, the **apply** job waits in `<env>-apply` until a named reviewer
   approves. Only then does GitHub issue the token the apply identity trusts. It downloads the
   saved plan, checks the hash, and applies exactly that plan; Terraform refuses it if the state
   moved since.

Stage `preflight` runs the read-only readiness check ([readiness.md](readiness.md)) as the plan
identity instead, and never applies. State lives at `avd/<env>/<stage>.tfstate`. Saved plans expire after 7 days.

## Who can do what

| Identity | Azure | Microsoft Graph | Trusted token |
|---|---|---|---|
| plan | Reader on the subscription, plus a custom role with only `retrieveRegistrationToken`. Reads state and answers; writes only the `plans` container | `Application.Read.All`, `Group.Read.All` | `repo:<owner>/<repo>:environment:<env>-plan`, from `main` only |
| apply | Contributor, and Role Based Access Control Administrator limited by a condition to the seven roles the platform stage assigns (Owner is refused). Writes state | `Application.Read.All` | `repo:<owner>/<repo>:environment:<env>-apply`, from `main` only, after approval |
| you (bootstrap) | Owner, or Contributor plus Role Based Access Control Administrator, once | Privileged Role Administrator through PIM, once, to grant the Graph roles | none |

Changes from nerdio-hcl's identities: the platform stage creates no Entra objects, so both Graph
grants are read-only and a test refuses a `ReadWrite` role on the apply identity. The assignable
roles are the AVD ones (Desktop Virtualization User, Power On Off Contributor, VM user and admin
login, Key Vault Secrets User, the two SMB share roles); Contributor is not assignable.

## Gotchas

- **Required reviewers need a public repository.** On GitHub Free, Pro and Team, required
  reviewers and wait timers on an environment work only in public repositories. GitHub Free can't
  use environments or environment secrets in a private repository at all; Pro and Team get
  environments, secrets and branch policies, but still no reviewers. Only Enterprise gets
  reviewers in a private repository
  ([GitHub docs](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)).
  So the module reads the repository's visibility and refuses to plan the apply environment for
  a private one unless `github.enterprise = true`, and `bootstrap.sh` stops before it starts.
  Until the repository is public, apply from Cloud Shell, where Terraform asks for yes.
- **Ephemeral resources open while Terraform plans.** The registration token
  (`modules/run-secrets`) is read during the plan as well as the apply, so a Reader-only plan
  identity fails once the host pool exists. `count` can't use `terraform.applying` (Terraform
  rejects an ephemeral value there), and an ephemeral variable set only at apply is refused too
  ("was not set during the planning phase, and so must remain unset"). The plan identity gets a
  custom role with that one action. The trade: anyone who can merge to `main` and start a plan
  could read a token that registers a machine until it expires (`registration_token_hours`).
  `plan_reads_registration_token = false` removes the role.
- **The plan identity can't touch what the apply acts on.** It needs no approval, so it only
  reads state and answers. That means it can't take the state lock (a blob lease is a write), so
  plans run with `-lock=false`: the workflow's concurrency group runs one job per environment,
  and Terraform refuses a saved plan whose state moved since.
- **The answers can't pick another environment.** `render --environment <env>` refuses answers
  whose `environment` differs from the one the run deploys, so a dev run can't plan sandbox's
  names under dev's state.
- **One folder, several environments.** `00-pipeline` keeps a working folder
  (`TF_DATA_DIR=.terraform-<env>`), a variables file and a backend (`backend_override.tf`,
  local first, then the new storage) per environment, all git-ignored, so bootstrapping dev never
  plans against sandbox's state. The storage each environment uses is remembered in
  `~/.config/avd-hcl/<env>.json` with its tenant and subscription.
- **Custom role names are unique across the tenant,** so the token role's name carries the
  subscription's hash as well as the pipeline name.
- **`-input=false` cancels an apply.** With it Terraform can't ask for yes, so `bootstrap.sh`
  leaves it off the one apply a person confirms.
- **A storage account name is 24 characters at most.** The pipeline's is
  `st<name without hyphens>tf<6 hex>`, so `name` follows the platform prefix rule (2 to 13
  characters), not nerdio-hcl's 15.
- **One owner per setting.** The pipeline owns the two GitHub environments, their branch policy,
  reviewers and secrets. Repository settings, the ruleset on `main` and labels belong to the
  `github/` settings ([github-settings-spec.md](github-settings-spec.md)), so nerdio-hcl's
  `modules/github-repo` is not ported.
- **IDs are masked, not secret.** Tenant, subscription, client and state names are environment
  secrets only so GitHub masks them in public logs; `stage.sh` also replaces every GUID it
  prints.

## tflint

CI runs tflint 0.64.0 with the azurerm ruleset 0.32.0 (`.tflint.hcl`) in every module and root.
The ruleset's `azurerm_resources_missing_prevent_destroy` is off: `prevent_destroy` can't vary by
environment and sandbox runs must tear down; soft delete, versioning and share retention keep
the data instead.
