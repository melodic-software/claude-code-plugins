# Changelog — discovery plugin

## 0.4.0 — 2026-07-14

Adopt the marketplace topic-docs convention, contract v1.0.0
(<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>):

- `EXPLORE.md` / `RESEARCH.md` are memory-tier artifacts written to
  `<memory_dir>/<slug>/` (default `.work/<slug>/`), never committed. The
  session's first memory-tier write verifies the **resolved memory
  root** contains a self-ignoring `.gitignore` (`*`), creating it
  (announced) when absent. No skill edits the consumer's root
  `.gitignore`.
- New `reference/topic-docs.md` — the plugin's **deltas-only** binding
  to the contract: its artifact/tier table. The contract owns the
  resolution order, slug spec, runtime guards, no-project-root
  fallback, and the non-interactive/forked mode the `-deep` variants
  run under; every skill resolves destinations by citing the binding,
  not by restating the rules.
- Slug derivation and sidecar filenames follow the contract's spec;
  skill-specific sidecars are `EXPLORE-<scope>.md` /
  `RESEARCH-<topic>.md`.
- `/discovery:setup` now interviews for and persists the tracked
  concern file `.claude/topic-docs.yaml` (previously the `notes_dir`
  pluginConfig), offering and preserving every schema key —
  `contract_dir`, `memory_dir`, `contract_tier`, `vault_backend` — and
  citing the schema by its raw URL. Order is guard-then-persist: the
  `git check-ignore -v` conflict check on the configured contract root
  runs BEFORE the concern file is written — and only when the chosen
  tier is `branch` (local mode has no committed tier to guard).
- Removed: the `notes_dir` userConfig option and the `.claude/notes/`
  layout. Prior locations are retired outright — no compatibility
  layer, no dual-read window, no migration tooling; move residual
  content manually.
