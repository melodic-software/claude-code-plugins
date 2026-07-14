# Changelog — session-flow plugin

## 0.3.0 — 2026-07-14

Adopt the marketplace topic-docs convention
(`docs/conventions/topic-docs/`, contract v1.0.0):

- Handoff save-points move from `.claude/handoffs/` to the memory
  tier's concern-scoped handoffs directory — `<memory_dir>/handoffs/`
  (default `.work/handoffs/`), never committed. The workflow
  checklist moves to the topic's own memory slice —
  `<memory_dir>/<slug>/workflow-checklist.md` (default
  `.work/<slug>/`), a per-topic stage ledger: a fixed filename in the
  shared handoffs directory would clobber across two in-flight
  topics. The session's first memory-tier write verifies the resolved
  memory root's self-ignore guard (a `.gitignore` containing `*`),
  creating it (announced) when absent. No skill edits the consumer's
  root `.gitignore`. A consumer-declared convention
  (`.claude/topic-docs.yaml`, `CLAUDE.md` / rules) still wins;
  filename timestamps stay ISO-basic UTC.
- New `reference/topic-docs.md` — the plugin's binding to the contract
  (memory tier, handoffs concern directory, resolution order, guards).
  The handoff, workflow, and retro skills resolve placement through
  it; none bakes its own paths.
- The prior `.claude/handoffs/` location is retired outright — no
  compatibility layer, no dual-read window, no migration tooling;
  move residual content manually.
