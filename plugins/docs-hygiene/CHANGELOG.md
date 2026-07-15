# Changelog — docs-hygiene plugin

## 0.5.0 — 2026-07-15

Changed:

- Renamed the `encapsulation-audit` skill → `audit-encapsulation`. Update any
  `/docs-hygiene:encapsulation-audit` invocations to `/docs-hygiene:audit-encapsulation`; the plugin ID
  (`docs-hygiene`) is unchanged, only the skill's leaf name moved.

## 0.4.0 — 2026-07-15

Added:

- Self-contained, bundled eval fixtures: compress's `audit-classification-table`
  case (`evals/fixtures/audit-fixture-dir/`) and declutter's
  `opt-out-and-section-exemptions-respected` case
  (`evals/fixtures/legit-optouts.md`) — both previously unfalsifiable prose
  prompts referencing nonexistent files.
- The "add an eval case" clause, re-added to the two Gotchas/Recheck-trigger
  bullets in rename-references/SKILL.md.

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
- Exemptions apply per matched path, not per line: the detector scans
  each candidate path individually, so a convention token (placeholder,
  bare concern root, concern file) no longer masks a concrete ghost ref
  sharing its line.
- The concern-root exemption narrows to the bare roots: `.work/handoffs/`
  and `.work/reviews/` are exempt only with nothing concrete after them
  (or an angle-bracket placeholder child) — a concrete child such as
  `.work/reviews/pr-123-auth/20260101T000000Z-self.md` flags.
- Candidate slugs accept a digit-leading first character, matching the
  convention's `[a-z0-9-]` slug spec and its recommended date-suffixed
  slugs (`docs/topics/2026-migration/PLAN.md` flags).
- The `.claude/topic-docs.yaml` exemption clause is removed: the concern
  file matches no ghost-ref pattern, so under the per-path model it
  passes naturally instead of exempting whole lines.
- The ghost-ref block short-circuits: a literal prefilter on `.work/`,
  `docs/topics/`, and `.claude/notes/` gates the scan, which stops at
  the first flagged path.
