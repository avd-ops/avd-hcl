# Instructions for AI assistants

Read [CLAUDE.md](CLAUDE.md) and [docs/guardrails.md](docs/guardrails.md) first. In addition:

- Never put API keys, tenant, subscription, object or client IDs, domains, IPs, emails, secrets,
  or employer or customer names in the repo, commits or PR text.
- Never ask for, show or store a secret in chat. The person runs the step that handles it.
- Propose changes as pull requests. Never change a real account, deployment or spend setting
  without the owner's explicit yes.
- Before building something new, check what exists (Azure Verified Modules, nerdio-hcl,
  avd-landing-zone) and record what you learned in `docs/knowledge/`.
- When code changes, record what was learned in `docs/knowledge/` in the same PR.
