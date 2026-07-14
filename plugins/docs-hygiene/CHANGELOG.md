# Changelog — docs-hygiene plugin

## 0.3.0 — 2026-07-14

Adopt the marketplace topic-docs convention
(`docs/conventions/topic-docs/`, contract v1.0.0) in the declutter
ghost-ref detector:

- Concrete `docs/topics/<slug>/` contract-slice paths are ghost-ref
  candidates alongside `.work/<slug>/` memory slices — contract slices
  are pruned before merge, so a durable doc citing one breaks.
- Any `.claude/notes/` citation is a ghost-ref candidate, placeholder
  form included — the location is retired under the convention.
- The exemption widens from the bare `.work/<slug>` / `.work/<sub-slug>`
  / `.work/<TS>` tokens to the convention's citable surfaces:
  angle-bracket slot variables under `.work/` and `docs/topics/`, the
  reserved concern-scoped roots `.work/handoffs/` and `.work/reviews/`,
  and the tracked concern file `.claude/topic-docs.yaml`.
