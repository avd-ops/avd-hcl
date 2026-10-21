---
status: accepted
date: 2026-10-21
decision-makers: [owner]
---

# 0004. HashiCorp community editions: Terraform, Vault and Packer

## Context and Problem Statement

[Decision 0001](0001-native-avd-with-the-hashicorp-stack.md) set the scope as Terraform, Packer
and "Vault or OpenBao where a secret store is needed", without weighing licenses. Terraform, Vault
and Packer are under the Business Source License 1.1 (free to use, source-available, not OSI open
source); OpenTofu and OpenBao are MPL-2.0 forks. The GitHub settings spec
([github-settings-spec.md](../github-settings-spec.md)) asked which tool and which secret store to
use. Which editions does the kit use?

## Considered Options

- HashiCorp community editions: Terraform, Vault and Packer
- The open source forks: OpenTofu and OpenBao, with Packer
- HashiCorp's hosted or paid editions (HCP Terraform, HCP Vault, Enterprise)

## Decision Outcome

Chosen option: "HashiCorp community editions", the owner's word on 2026-10-21 ("i want to use
vault/tf community editions", "vault for secrets", "packer for image pipeline").

- **Terraform Community Edition** for the estate and for this repository's GitHub settings.
- **Vault Community Edition** is the secret store, self-hosted. Secrets the kit hands out, and
  signing keys such as GitHub App keys, live in Vault; Azure Key Vault is used only where Azure
  itself needs a key (for example Vault's auto-unseal key) or a VM reads a secret by managed
  identity.
- **Packer** for the image pipeline (port plan, question 4).
- No paid or hosted HashiCorp product, and no account with HashiCorp.

### Consequences

- Good, because one vendor's tools, docs and HCL conventions across the whole kit.
- Good, because nothing costs a license, and the kit runs from Cloud Shell with the CLIs.
- Bad, because the BSL is not an open source license: a fork or a hosted service built on the kit
  must check the BSL's terms. The kit's own code stays Apache-2.0.
- Bad, because self-hosted Vault is a running server to keep patched, unsealed and backed up; the
  kit builds it from config (nerdio-hcl's OpenBao module is the starting point) so it can be
  replaced rather than repaired.
- Neutral, because the code avoids features OpenTofu or OpenBao lack where that costs nothing, so a
  later switch stays possible; it is not a goal.

## More Information

OpenTofu and OpenBao stay as prior art. nerdio-hcl uses OpenBao for its optional secret server;
porting that module to Vault CE is credited in CREDITS.md when it lands.
