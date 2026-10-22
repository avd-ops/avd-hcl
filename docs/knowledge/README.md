---
title: "Knowledge base"
summary: "What avd-hcl has learned and decided: the port plan, decision records and, later, gotchas from real runs"
topic: overview
status: plan
last_reviewed: 2026-10-21
---

# Knowledge base

What this kit learns while porting nerdio-hcl's approach to native Azure Virtual Desktop with the
HashiCorp stack. When something new is learned, add it to the page it belongs to instead of
starting a new file. A fact that belongs to avd-landing-zone or nerdio-hcl gets a link to their
page, not a copy.

- [port-plan.md](port-plan.md): what maps from nerdio-hcl, what is redesigned, what is new, open
  questions and the phased order.
- [platform.md](platform.md): what the platform stage builds, where each module comes from,
  and the gotchas found writing it.
- [pipeline.md](pipeline.md): the gated deploy pipeline, who can do what, and why a private
  repository can't use it yet.
- [readiness.md](readiness.md): the read-only check before the platform stage, every check and
  the right it needs.
- [decisions/](decisions/): decision records in MADR 4 format.
- [github-settings-spec.md](github-settings-spec.md): this repository's GitHub settings as
  Terraform in `github/`, with a read-only drift check (proposed).

avd-hcl is a standalone project, not part of the avd-ops family. KB tooling (index generation,
validation, prior-art and freshness checks) may be added later; it isn't installed yet.
