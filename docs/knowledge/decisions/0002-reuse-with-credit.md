---
status: accepted
date: 2026-10-21
decision-makers: [owner]
---

# 0002. Reuse what exists, with full credit; Apache-2.0

## Context and Problem Statement

nerdio-hcl (Apache-2.0) already has the guided phases, parameter schema, gated pipeline,
readiness engine and Packer build; avd-landing-zone (MIT) already has the estate design and the
lessons from real runs; Microsoft publishes Azure Verified Modules for AVD in Terraform. Building
these again would waste the work and repeat the mistakes. How does the kit reuse them, and under
which license?

## Considered Options

- Reuse freely with full credit, under Apache-2.0
- Reuse under MIT
- Write everything from scratch

## Decision Outcome

Chosen option: "Reuse freely with full credit, under Apache-2.0", because the owner wants nothing
reinvented and Apache-2.0 is the enterprise-friendly choice that also matches nerdio-hcl.

- A file that starts as someone else's keeps a header naming its source and license.
- Every reuse, of code, design or facts, gets a row in [CREDITS.md](../../../CREDITS.md); a new
  upstream also gets a NOTICE entry. MIT code keeps its copyright and permission notice (in NOTICE).
- Adopt a third-party module only if it is the best option and open source; otherwise write our
  own and say why.
- Never copy from Nerdio's own repositories or other code with no license: facts only.

### Consequences

- Good, because the kit starts from tested design instead of a blank page.
- Good, because Apache-2.0 adds a patent grant and is on most companies' approved lists.
- Bad, because every reuse costs a CREDITS row and sometimes a NOTICE entry.
