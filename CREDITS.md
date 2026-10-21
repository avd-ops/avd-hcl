# Credits

Everything avd-hcl takes from another project is listed here, with its source, license and
commit. A file that started as someone else's keeps a header comment naming where it came from.
Ideas and facts are credited too, not only code ([decision 0002](docs/knowledge/decisions/0002-reuse-with-credit.md)).

| What | From | License | Commit | How |
|---|---|---|---|---|
| Overall approach: eight guided phases, one parameter schema for chat, CLI and forms, keyless gated pipeline, read-only readiness, Cloud Shell first | [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl) | Apache-2.0 | `75f59bc` | Design, in our own words ([port plan](docs/knowledge/port-plan.md)) |
| Estate design and real-run lessons (FSLogix with Entra Kerberos, AVD Insights, image pipeline with WDOT, blue/green rotation, auto shutdown, readiness) | [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) | MIT | `91c7acf` | Design and lessons, by link |
| `modules/foundation`, `modules/network`, `modules/fslogix-storage` and their tests, the platform root's provider block and backend example, `schema/README.md` format | [nerdio-hcl](https://github.com/nickprignano/nerdio-hcl) | Apache-2.0 | `75f59bc` | Adapted; each file's header says what changed |
| `modules/key-vault`, `modules/monitoring`, `modules/control-plane`, `modules/session-hosts`: design, names, schedules, counters and RDP defaults | [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) `bicep/modules/` | MIT | `91c7acf` | Rewritten in Terraform; each file's header names its Bicep module |
| `modules/session-hosts/scripts/Register-AvdAgent.ps1`, `Set-FSLogixConfiguration.ps1` | [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) `scripts/sessionhost/` | MIT | `91c7acf` | Copied; help text points at the Terraform module |
| Fail-closed gitleaks pre-commit hook and full-history CI scan | This repo's earlier lab kit (same author) | MIT, same author | `de2b9bc` | Kept and edited |

Add a row in the same pull request that brings something in.
