# Changelog — discovery plugin

## 0.4.0 — 2026-07-14

Adopt the marketplace topic-docs convention
(`docs/conventions/topic-docs/`, contract v1.0.0):

- `EXPLORE.md` / `RESEARCH.md` are memory-tier artifacts written to
  `<memory_dir>/<slug>/` (default `.work/<slug>/`), never committed,
  with a self-ignore guard (`.gitignore` containing `*`) verified or
  created before every write. No skill edits the consumer's root
  `.gitignore`.
- New `reference/topic-docs.md` — the plugin's binding to the contract
  (per-artifact tiers, resolution ladder, slug spec, guards, legacy
  grace). Every skill resolves the destination through its ladder:
  `.claude/topic-docs.yaml` concern file → consumer `CLAUDE.md`/rules
  convention → legacy `notes_dir` knob (deprecation grace) → inferred
  conforming layout → ask once → documented defaults. Outside a project
  root, non-interactive writes target
  `${CLAUDE_PLUGIN_DATA}/topic-docs/<slug>/` only.
- Slug derivation and sidecar filenames now follow the contract's spec:
  kebab-case ≤40 chars, Windows-reserved-name `-x` suffixing,
  resume-vs-collision rules, `EXPLORE-<scope>.md` /
  `RESEARCH-<topic>.md` sidecars.
- `/discovery:setup` now interviews for and persists the tracked
  concern file `.claude/topic-docs.yaml` (previously the `notes_dir`
  pluginConfig), runs the `git check-ignore -v` conflict check on the
  configured contract root, and offers a guarded migration of legacy
  `.claude/notes/<slug>` content.
- Deprecated: the `notes_dir` userConfig option (its `.claude/notes`
  default is removed so only an explicit value resolves). When set — or
  when `.claude/notes/<slug>` content exists — skills operate wholly on
  the old location (reads and writes) and emit a deprecation notice.
  The knob and dual-read are removed at the next major version.
