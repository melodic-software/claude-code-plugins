# Changelog — standards convention

## 1.0.0 — 2026-07-17

Initial contract:

- Three additive layers on one precedence-inversion rule: user-global
  `~/.claude/standards/`, team-tracked `<standards_dir>/` (default
  `docs/standards/`), gitignored `*.local.md` personal overlays. Personal
  layers add or tighten only; direct conflict → team wins; provenance
  named when a personal rule shapes output.
- Thin routing index at `<standards_dir>/README.md` with a normative
  presence test (`standards-contract` frontmatter key), Surface /
  Applies-when / File columns, external rows with a validation duty, and
  forward-slash paths against the git top-level resolution root.
- SRP standards files (pure prose, no frontmatter) with a soft ~200-line
  size budget and selective section reads.
- Tracked concern file `.claude/standards.yaml` (`standards_dir`), shaped
  by `standards.schema.json`.
- Six-rung resolution ladder with a no-silent-writes guarantee, an
  ambient-content rule, and a tolerant-reader rule.
- `.claude/rules` division-of-content seam: rules push, standards pull;
  pointer pattern instead of imports or restated content.
- Normative setup-and-migration procedure: idempotent re-runnable
  bootstrap (run twice, no diff), conforming-index short-circuit,
  hand-authored-README confirmation gate, setup-owned
  `<standards_dir>/.gitignore` for overlays, and DIRECTIONAL version-delta
  handling (older index → guided migration; newer index → best-effort
  read plus "update the plugin", never a downgrade).
