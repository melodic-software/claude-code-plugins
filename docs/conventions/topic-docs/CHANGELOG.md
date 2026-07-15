# Changelog — topic-docs convention

## 1.0.0 — 2026-07-14

Initial contract. Replaces four divergent conventions
(`.claude/notes/<slug>`, `.claude/handoffs/`, `.claude/review/`, legacy
unscoped `.work/<slug>`) with:

- Two tiers on one slug: memory (`.work/<slug>/`, self-ignoring) and
  contract (`docs/topics/<slug>/`, committed on the task branch, pruned
  before merge with context pointers).
- Tracked concern file `.claude/topic-docs.yaml` as the consumer-side
  SSOT, with a six-rung resolution order and legacy `notes_dir` knobs as
  a deprecation grace path.
- Runtime guards: committed-tier `git check-ignore` assertion; memory
  self-ignore verify-or-create; no consumer root-`.gitignore` edits.
- Windows-safe slug and filename spec; single-home rule; redaction bar
  for committed evidence.
- Graduation edges: work-item tracker seam (tickets) and knowledge-vault
  seam (durable docs; in-repo `docs/` default backend).
- Removed kinds: `history.md`; default-persisted `brainstorm.md`.
