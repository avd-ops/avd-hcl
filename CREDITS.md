# Credits

Everything avd-hcl takes from another project is listed here, with its source, license and
commit. A file that started as someone else's keeps a header comment naming where it came from.
Ideas and facts are credited too, not only code ([decision 0002](docs/knowledge/decisions/0002-reuse-with-credit.md)).

| What | From | License | Commit | How |
|---|---|---|---|---|
| Overall approach: eight guided phases, one parameter schema for chat, CLI and forms, keyless gated pipeline, read-only readiness, Cloud Shell first | [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl) | Apache-2.0 | `75f59bc` | Design, in our own words ([port plan](docs/knowledge/port-plan.md)) |
| Estate design and real-run lessons (FSLogix with Entra Kerberos, AVD Insights, image pipeline with WDOT, blue/green rotation, auto shutdown, readiness) | [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) | MIT | `91c7acf` | Design and lessons, by link |
| `modules/foundation`, `modules/network` (and its tests), `modules/fslogix-storage`, the platform root's provider block and backend settings, `schema/README.md` format | [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl) | Apache-2.0 | `75f59bc` | Adapted; each file's header says what changed |
| `modules/key-vault`, `modules/monitoring`, `modules/control-plane`, `modules/session-hosts`: design, names, schedules, counters, budget, auto-shutdown, blue/green generation naming and RDP defaults | [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) `bicep/modules/` | MIT | `91c7acf` | Rewritten in Terraform; each file's header names its Bicep module |
| `modules/image-gallery` (and its tests), `environments/example/02-images`, `packer/avd-win11` | [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl) and [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) | Apache-2.0 / MIT | `75f59bc` / `91c7acf` | Adapted; `03-wdot.ps1` adds the landing zone's event-log pre-creation and `HKLM:\SOFTWARE\WDOT` verification (lesson 0031) |
| `modules/session-hosts/scripts/Register-AvdAgent.ps1`, `Set-FSLogixConfiguration.ps1` | [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) `scripts/sessionhost/` | MIT | `91c7acf` | Copied; help text points at the Terraform module |
| `modules/deploy-pipeline` (and its tests), `environments/example/00-pipeline`, `.github/workflows/deploy.yml`, `scripts/pipeline/stage.sh`, `scripts/pipeline/bootstrap.sh` | [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl) | Apache-2.0 | `75f59bc` | Adapted; each file's header says what changed |
| `scripts/readiness/` (model, context, runner, report and the op, identity, subscription, network and avd checks), `scripts/preflight.py` | [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl) `scripts/nerdio/readiness/` | Apache-2.0 | `75f59bc` | Adapted; Nerdio checks removed, AVD checks added; each file's header says what changed |
| `scripts/schema/answers.py`: the idea of one `init` and render step over the schema | [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl) `./nerdio init` | Apache-2.0 | `75f59bc` | Design only; written new |
| Fail-closed gitleaks pre-commit hook and full-history CI scan | This repo's earlier lab kit (same author) | MIT, same author | `de2b9bc` | Kept and edited |
| GitHub repository settings module (labels, read-only workflow token, ruleset on the default branch) | [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl) `modules/github-repo` | Apache-2.0 | `75f59bc` | Adapted in `github/modules/repo-settings` |
| GitHub App token from a non-exportable Key Vault key (Key Vault signs the JWT) | [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl) `assistant/pipeline.py` | Apache-2.0 | `75f59bc` | Adapted in `github/scripts/app_token.py` |
| GitHub work conventions (merge commits, required checks, admin bypass for pull requests, labels) and secrets handling | [avd-second-brain](https://github.com/avd-ops/avd-second-brain) decisions 0013, 0014, 0015 and hub decision 0016 | MIT | `main` | Conventions, in our own words (`github/conventions.md`) |

Add a row in the same pull request that brings something in.
