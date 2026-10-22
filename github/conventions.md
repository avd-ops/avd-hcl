# GitHub conventions for this repository

The settings `github/modules/repo-settings` sets, and where each comes from. A change to a
convention is a pull request that changes the module and this table together. The design is in
[the spec](../docs/knowledge/github-settings-spec.md); "0011", "0012", "0014" and "0016" are
[ai-brain's decisions](https://github.com/nickprignano/ai-brain/tree/aee6a18/docs/knowledge/decisions).
nerdio-hcl, the owner's other HCL repository, can match this table from its own project.

| Setting | Value | Source |
|---|---|---|
| Merge commits | allowed, title "merge message", message "PR title" | 0014 (merge commits) |
| Squash and rebase merges | off | proposed here: one merge method |
| Allow auto-merge | off; `kb_auto_merge = true` turns it on and requires the `auto-merge` check together | 0014, section 3 |
| Delete head branch on merge | on | proposed here |
| Update branch button | off | proposed here |
| Issues | on | needed by the drift issue; the provider's default is off |
| Wiki, Projects, Discussions | off | proposed here |
| Ruleset on the default branch | pull request required, 0 approvals, merge commits only, no deletion or force push, required checks from GitHub Actions only, not strict | 0014, section 3; 0016, step 6 |
| Ruleset bypass | repository admin role, pull requests only | 0014, section 3 |
| Ruleset switch | `enforce_ruleset`, off until GitHub Pro or a public repository | GitHub plans |
| Labels | `no-kb`, `no-auto-merge`, `handoff`, `handoff-proposed`, `drift`, plus `extra_labels` | 0011, 0014, 0012; `drift` is the drift check's |
| Dependabot alerts and security updates | on | proposed here |
| Secret scanning and push protection | on only for a public repository | 0016, step 11; not offered on a personal account's private repositories |
| Default workflow token | read-only; Actions can't approve pull requests | proposed here |
| GitHub environments | not managed here: the deploy pipeline owns them | one owner per setting |
| Repository | `prevent_destroy`, archived (never deleted) on destroy | proposed here |
