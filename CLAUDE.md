@AGENTS.md

# CLAUDE.md

avd-hcl: native Azure Virtual Desktop deployed and operated with Terraform and Packer community
editions, secrets in Azure Key Vault, no Vault server (decision 0004; Ansible only if a decision
record shows it earns its place). It ports the approach of
nerdio-hcl without Nerdio, and follows avd-landing-zone's estate design without depending on it.
The plan is `docs/knowledge/port-plan.md`; decisions are in `docs/knowledge/decisions/`.

## Rules
- Read [docs/guardrails.md](docs/guardrails.md) before changing anything.
- **Private for now.** Never name this repo, or link it, from a public repo, issue or PR until
  the owner makes it public.
- **avd-landing-zone stays fully separate.** It never depends on this kit, and nothing here
  writes to it. Reuse its design and lessons freely, with credit.
- **Credit what you take.** A reused file keeps a header naming its source; every reuse gets a
  row in `CREDITS.md` and, for a new upstream, a NOTICE entry. nerdio-hcl is Apache-2.0,
  avd-landing-zone is MIT. Never copy from Nerdio's own repositories or other unlicensed code.
- **No Nerdio in the path:** no `nerdio/nme` provider, no Nerdio API, wizard or paid tool.
- **No cloud run without a written cost estimate and the owner's exact go**
  (`go batch <id> $<total>`); a bare "go" is not approval. Smallest sizes, tear down right after,
  with teardown evidence.
- Prefer Azure Verified Modules for Terraform where they are the best open-source option;
  otherwise write our own and say why in a decision record.
