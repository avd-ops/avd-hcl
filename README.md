# avd-hcl

> **Personal project, not for production.** Provided as is, with no warranty. Not affiliated with
> or endorsed by the author's employer, Microsoft, HashiCorp or Nerdio.

Native Azure Virtual Desktop, deployed and operated with the HashiCorp stack: Terraform for the
estate, Packer for golden images, Vault (or OpenBao) where a secret store is needed, and Ansible
only if it turns out to earn its place. No vendor management plane sits in the path.

**Status: phase 0, setup.** There is no Terraform here yet. The plan is
[docs/knowledge/port-plan.md](docs/knowledge/port-plan.md).

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

## License

[Apache License 2.0](LICENSE). Components the kit downloads or calls keep their own terms; see
[NOTICE](NOTICE).
