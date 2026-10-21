---
status: accepted
date: 2026-10-21
decision-makers: [owner]
---

# 0004. Terraform and Packer community editions; Azure Key Vault, not Vault, for secrets

## Context and Problem Statement

[Decision 0001](0001-native-avd-with-the-hashicorp-stack.md) set the scope as Terraform, Packer
and "Vault or OpenBao where a secret store is needed", without weighing licenses or what a secret
server costs to run. Terraform, Vault and Packer are under the Business Source License 1.1 (free
to use, source-available, not OSI open source); OpenTofu and OpenBao are MPL-2.0 forks. The GitHub
settings spec ([github-settings-spec.md](../github-settings-spec.md)) asked which tool and which
secret store to use. Which editions does the kit use, and does it run Vault?

## Considered Options

- Terraform and Packer community editions, with Vault Community Edition as the secret store
- Terraform and Packer community editions, with Azure Key Vault and managed identities, no Vault
- The open source forks: OpenTofu and OpenBao, with Packer
- HashiCorp's hosted or paid editions (HCP Terraform, HCP Vault Dedicated, Enterprise)

## Decision Outcome

Chosen option: "Terraform and Packer community editions, with Azure Key Vault", the owner's word on
2026-10-21 ("i want to use vault/tf community editions", "packer for image pipeline", then, after
weighing what Vault would cost to run, "ok lets pivot, no valult just tf").

- **Terraform Community Edition** for the estate and for this repository's GitHub settings.
- **Packer** for the image pipeline (port plan, question 4).
- **No Vault server.** Azure Key Vault holds the secrets and keys the kit needs (including
  sign-only keys such as GitHub App keys), managed identities and OIDC federation sign everything
  in, and Terraform keeps secrets out of state with ephemeral reads and write-only attributes.
- No paid or hosted HashiCorp product, and no account with HashiCorp.

Why not Vault: Vault Community Edition is a server to run, patch, unseal and back up (about $12 to
$15 a month as the smallest always-on VM), and the managed HCP Vault Dedicated starts at about
$450 a month; HCP Vault Secrets, the cheap managed option, reached end of life on 2026-07-01. For
native AVD on Azure, Key Vault and managed identities already cover what Vault would do. Vault
would earn its place only for (a) rotating or checking out an on-premises AD domain join account
per run, or (b) a vendor API that only accepts long-lived client secrets (nerdio-hcl's reason for
its optional OpenBao server). Either one reopens this decision.

### Consequences

- Good, because nothing extra runs or bills; Key Vault costs cents a month at this scale.
- Good, because one secret store that Azure's own identities already reach.
- Bad, because the BSL is not an open source license: a fork or a hosted service built on the kit
  must check the BSL's terms. The kit's own code stays Apache-2.0.
- Bad, because the repository's name promises more of the HashiCorp stack than it uses.
- Neutral, because the code avoids features OpenTofu lacks where that costs nothing, so a later
  switch stays possible; it is not a goal.

## More Information

OpenTofu, OpenBao, Vault Community Edition and HCP Vault stay as prior art. nerdio-hcl's
`modules/openbao` is the starting point if Vault is ever reopened.
