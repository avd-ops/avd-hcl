# avd-hcl

> **Personal project, not for production.** Provided as is, with no warranty. Not affiliated with
> or endorsed by the author's employer, Microsoft, HashiCorp or Nerdio.

Native Azure Virtual Desktop, deployed and operated with the HashiCorp stack: Terraform for the
estate, Packer for golden images, Vault (or OpenBao) where a secret store is needed, and Ansible
only if it turns out to earn its place. No vendor management plane sits in the path.

**Status: phase 1, built and tested offline only.** The platform stage builds one pooled,
Entra-joined host pool with FSLogix, autoscale and AVD Insights; it has not run against Azure yet.
The plan is [docs/knowledge/port-plan.md](docs/knowledge/port-plan.md); what is built is
[docs/knowledge/platform.md](docs/knowledge/platform.md).

## Layout

| Path | What |
|---|---|
| `modules/` | One module per role: foundation, network, fslogix-storage, key-vault, monitoring, control-plane, session-hosts, and run-secrets for the values that never touch state. Each has `tests/` for `terraform test`, except run-secrets, tested through the root |
| `environments/example/01-platform/` | The platform root that wires the modules together; copy it per environment |
| `schema/parameters.json` | The one list of deployment parameters behind every front door |
| `scripts/schema/` | The schema check CI runs, and `answers.py` (`init` asks the questions, `render` writes the tfvars) |
| `modules/deploy-pipeline/`, `environments/example/00-pipeline/` | The gated pipeline: state storage, plan and apply identities, GitHub environments |
| `scripts/preflight.py`, `scripts/readiness/` | The read-only readiness check before the platform stage |
| `scripts/pipeline/` | `bootstrap.sh` (one-time setup from Cloud Shell) and `stage.sh` (what the Deploy workflow runs) |

## Try it offline

From Cloud Shell, with no Azure changes (mock providers only):

```bash
git clone https://github.com/nickprignano/avd-hcl.git && cd avd-hcl
for d in modules/*/ environments/example/*/; do [ -d "$d/tests" ] && (cd "$d" && terraform init -backend=false >/dev/null && terraform test); done
python3 scripts/schema/check.py && python3 -m unittest discover -s scripts/schema
python3 -m unittest discover -s scripts/readiness -t scripts
```

## Where it comes from

- **[nerdio-hcl](https://github.com/nickprignano/nerdio-hcl)** (Apache-2.0) for the approach: a
  guided setup in eight phases, one parameter schema behind the chat, the CLI and the Actions
  form, a keyless pipeline where nothing applies without a reviewer's yes, and a read-only
  readiness check. Everything that exists only to talk to Nerdio Manager is left out.
- **[avd-landing-zone](https://github.com/avd-ops/avd-landing-zone)** (MIT) for what a good AVD
  estate looks like and the lessons from its real runs. The landing zone is Bicep and stays
  fully separate; it never depends on this kit.

Full credits: [CREDITS.md](CREDITS.md) and [NOTICE](NOTICE).

## Rules in short

- HCL first; scripts only as thin bootstrap glue. Everything works from Azure Cloud Shell, an iPad
  included.
- Keyless: workload identity federation and managed identities, Key Vault for any hand-off.
- Least privilege, every right written down; privileged roles through PIM; no Global Admin
  shortcuts.
- Plan first, every change a pull request, nothing applies without an explicit yes.
- Nothing identifies a real environment. Real values live in git-ignored tfvars.

Details: [docs/guardrails.md](docs/guardrails.md).

## Contributing

Turn on the secret-scanning pre-commit hook once per clone. It fails closed if gitleaks is
missing and prints how to install it in Cloud Shell:

```bash
git config core.hooksPath .githooks
```

CI runs the same scan over full history, `terraform fmt`, `validate` and `test` in every module
and root, the schema check, and the guards in `.github/workflows/ci.yml`. Every reuse gets a row
in [CREDITS.md](CREDITS.md), and a public Microsoft ID gets a line in `.github/public-ids.txt`.

## License

[Apache License 2.0](LICENSE). Components the kit downloads or calls keep their own terms; see
[NOTICE](NOTICE).
