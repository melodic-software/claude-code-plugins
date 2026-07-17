# Contract spec — `standards` concern (design output)

The WHAT for /architect. Layers, precedence inversion, resolution ladder, and
setup mode are locked in the Brief (`../PLAN.md`) and are not restated here.
Decision rationale lives in `design-threads.md`. At implementation this spec
becomes `docs/conventions/standards/README.md` (+ `CHANGELOG.md`), following
the marketplace convention template.

## Index

Location: `<standards_dir>/README.md` (default `docs/standards/`).

```markdown
---
standards-contract: 1.0.0
---
# Standards index

| Surface | Applies when | File |
|---|---|---|
| csharp | **/*.cs; C# design or review tasks | csharp.md |
| testing | test strategy, writing or reviewing tests | testing.md |
| engineering-philosophy | any non-trivial design decision | ../engineering-philosophy.md |
```

- Routing only — no standards content in the index (an index is not a store).
  A short scope preamble is allowed.
- `standards-contract` (semver) is the only frontmatter key in v1; it names
  the contract version the index conforms to.
- One row per file; a surface id may span multiple rows.

### Columns

| Column | Form | Notes |
|---|---|---|
| Surface | free-form kebab-case id | Recommended kinds (not mandatory): ecosystem surfaces (`csharp`, `python`, `markdown`, …); cross-cutting concerns (`security`, `testing`, `naming`, `commits`, `architecture`, …). No stage axis — one SSOT for plan-time and review-time |
| Applies when | free-form context clues | File globs and/or task keywords; the model matches task context against them |
| File | repo-relative path | In-root rows: bare filename. External rows: repo-relative path outside the root — allowed (adoption without reorg), subject to the validation duty below |

### External rows — validation duty

- Setup validates every listed path exists on each run.
- A skill that hits a broken row surfaces it and offers the fix (Boy Scout) —
  never silent, never skipped quietly.
- Consumers are recommended to include the index in their link-check lane
  (e.g. lychee).

## Standards files

- `<surface>.md`, kebab-case, pure prose — no frontmatter, no metadata
  (clues live in the index; single home). Subdirectories allowed; the index
  row carries the relative path.
- SRP: one concern per file (Brief, progressive disclosure).

## Personal overlays (in-root only)

- `<name>.local.md` overlays `<name>.md` by filename convention; a
  `.local.md` with no base file is a standalone personal standard.
- Glob-discovered, never indexed (a tracked index cannot list gitignored
  files). Setup ships the `.gitignore` line `<standards_dir>/*.local.md`.
- Semantics per Brief: additive/tighten-only; direct conflict → team wins;
  provenance named when a personal rule materially shapes output.

## User-global layer

- `~/.claude/standards/` — optional own `README.md` index (same schema, same
  frontmatter), degrade to glob discovery when absent.
- Location fixed in v1; relocation deferred (trigger: real need).

## Concern file — `.claude/standards.yaml`

```yaml
# committed, team-shared; absent = all defaults
standards_dir: docs/standards
```

- Written by interactive setup only when the consumer relocates the root.
- Resolution: concern file → default `docs/standards/` → CLAUDE.md-declared
  location (inference source — offer to persist) → infer / ask once → safe
  default (Brief ladder).
- Rationale for a tracked file over `userConfig`: verified this session —
  `pluginConfigs` is user-settings-only and per-plugin; a team value consumed
  by two plugins cannot live there.

## `.claude/rules` seam (division-of-content rule)

- **Rules = push** (fire on matching file reads): short imperative directives,
  consumer-owned.
- **Standards = pull** (index-routed at plan/review stages): substantial
  criteria and prose.
- **Pointer pattern**: a path-scoped rule may carry an imperative pointer
  directive to a standards file ("Before editing C#, read
  `docs/standards/csharp.md`") — lazy load on rule fire. Never `@import`
  (expands at launch; undocumented inside rules), never restated content.
- Setup MAY offer generating pointer rules for indexed ecosystem surfaces
  (interactive only — the `.claude/` write-guard prompt is acceptable there).
- Grounding steps never re-pull content a fired rule already injected.

## Versioning and migration

- Contract semver lives in `docs/conventions/standards/CHANGELOG.md`; the
  consumer index records its conformance version in `standards-contract`.
- Additive schema change → minor; breaking (column/key/semantics change) →
  major + migration note + consuming-plugin version bumps.
- **Migration lives inside re-runnable setup** — no separate action. Setup
  compares index frontmatter to the bundled contract version, explains the
  delta, and offers guided migration. Idempotent: re-run after migration →
  no diff.
- Tolerant readers: a skill reading an older-version index degrades to
  best-effort routing and surfaces "index at vX, contract at vY — re-run
  setup to migrate". No auto-rewrite (no silent writes).

## Consumers (pilot)

- `planning:architect` — proactive standards step grounds plan formulation in
  index-routed sections for the surfaces the task touches; depth rides
  existing plan-scale/blast-radius gates.
- `review:quality-gate` `criteria` mode — resolves criteria through the same
  index (build/review symmetry).
- Each carries a synced `reference/` binding copy of the contract; sync
  mechanics and in-body step placement → /architect.
