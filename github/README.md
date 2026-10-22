# github/: this repository's GitHub settings

Terraform for avd-hcl's own GitHub settings, kept apart from the kit: its own module, root and
state. Design and open questions: [the spec](../docs/knowledge/github-settings-spec.md);
settings and their sources: [conventions.md](conventions.md).

- `modules/repo-settings/`: the settings, tested offline with a mock provider.
- `repos/avd-hcl/`: this repository's root, with an import block for every object that exists.
- `scripts/app_token.py`: a short-lived GitHub App token, signed by a Key Vault key that can't be
  read back. Used by the drift check, and by your applies once the bootstrap is done.
- `.github/workflows/github-drift.yml`: the daily read-only plan that opens a `drift` issue. It
  stays off until the bootstrap sets the repository variables, and it never applies.

Nothing here runs without you. Applies happen only from Cloud Shell, by you.

## First plan (read-only, changes nothing)

1. Create a [fine-grained token](https://github.com/settings/personal-access-tokens/new):
   expiry tomorrow, **Only select repositories: avd-hcl**, repository permissions
   **Administration: Read-only**, **Issues: Read-only** (Metadata is added automatically).
2. Paste this block in Cloud Shell (Bash) and paste the token when it asks. Nothing is echoed.

```bash
cd ~ && { [ -d avd-hcl ] && git -C avd-hcl pull -q || gh repo clone nickprignano/avd-hcl; } \
  && cd ~/avd-hcl/github/repos/avd-hcl \
  && read -rsp "Read-only token: " GITHUB_TOKEN && echo && export GITHUB_TOKEN \
  && terraform init -input=false -no-color >/dev/null \
  && terraform plan -input=false -no-color | tee ~/github-first-plan.txt; unset GITHUB_TOKEN
```

3. Share `~/github-first-plan.txt` (it holds setting names and values, no secrets), then revoke
   the token on GitHub.

## First apply (only after your go and after PR #10 merges)

The same block with a token that has **Administration: Read and write** and **Issues: Read and
write**, and `terraform apply` in place of `terraform plan`. Terraform shows the plan again and
asks for `yes`. Revoke the token after.
