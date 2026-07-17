---
standards-contract: 1.0.0
---

# Standards Convention

A versioned, marketplace-wide contract for how skills discover and load a
consuming repository's **standards** — its adopted code conventions,
engineering philosophy, and review criteria. One thin index routes tasks
to SRP-organized standards files; planning-stage and review-stage skills
resolve through the same index, so work is built to the criteria it will
be reviewed against.

This directory is the source of truth: this README (index schema, layers,
precedence, resolution ladder, setup and migration),
`standards.schema.json` (the tracked concern file's shape), `CHANGELOG.md`
(version history), `examples/` (one worked index). Consuming plugins carry
a synced, byte-identical binding copy at `reference/standards-contract.md`;
the `standards-contract` frontmatter key above names the contract version a
copy or a consumer index conforms to.

This file is synced verbatim into plugin binding copies, so it contains no
relative markdown links — neighboring files are named in backticks instead.

## Layers and precedence

Three layers, discovered independently, applied additively:

| Layer | Location | Git | Scope |
|---|---|---|---|
| User-global | `~/.claude/standards/` | untracked (user's machine) | personal, all projects |
| Team | `<standards_dir>/` (default `docs/standards/`) | committed, team-shared | the repository |
| Personal overlay | `<standards_dir>/*.local.md` | gitignored | personal, this repository |

**Precedence inversion:** layers are additive. Personal layers (user-global
and overlay) may ADD new standards or TIGHTEN team ones; on a direct
conflict, the team-tracked layer wins. When a personal-layer rule
materially shapes a skill's output, the skill names the contributing layer
(provenance), so reviewers can tell a team standard from a personal one.

The team layer deliberately lives outside `.claude/` — writes under
`.claude/` are permission-guarded, while reads and writes of ordinary
repo docs are not.

## The index

Location: `<standards_dir>/README.md`. It is a routing map, not a store:
rows map task context to standards files, and no standards content lives
in the index itself. A short scope preamble is allowed.

```markdown
---
standards-contract: 1.0.0
---

# Standards index

| Surface | Applies when | File |
|---|---|---|
| csharp | **/*.cs; C# design or review tasks | csharp.md |
| testing | test strategy, writing or reviewing tests | testing.md |
| engineering-philosophy | any non-trivial design decision | docs/engineering-philosophy.md |
```

- `standards-contract` (semver) is the only frontmatter key in v1; it names
  the contract version the index conforms to.
- One row per file; a surface id may span multiple rows.

**Presence test (normative):** an index exists if and only if the file
carries the `standards-contract` frontmatter key. A
`<standards_dir>/README.md` without that key is pre-existing, hand-authored
content — skills treat it as an inference source only, and setup requires
explicit confirmation before any conversion (see Setup and migration).

### Columns

| Column | Form | Notes |
|---|---|---|
| Surface | free-form kebab-case id | Recommended kinds (not mandatory): ecosystem surfaces (`csharp`, `python`, `markdown`, …); cross-cutting concerns (`security`, `testing`, `naming`, `commits`, `architecture`, …). No stage axis — one SSOT serves plan-time and review-time |
| Applies when | free-form context clues | File globs and/or task keywords; the model matches task context against them |
| File | forward-slash path | In-root rows: path relative to `<standards_dir>` (bare filename, or a subdirectory path). External rows: repo-relative path from the resolution root — allowed (adoption without reorg), subject to the validation duty below. Always forward slashes, on every platform |

### External rows — validation duty

- Setup validates every listed path exists on each run.
- A skill that hits a broken row surfaces it and offers the fix (Boy
  Scout) — never silent, never skipped quietly.
- Consumers are recommended to include the index in their link-check lane.

## Standards files

- `<surface>.md`, kebab-case, pure prose — no frontmatter, no metadata
  (context clues live in the index; single home). Subdirectories allowed;
  the index row carries the relative path.
- SRP: one concern per file (progressive disclosure — skills pull only the
  files whose rows match the task).
- **Size guidance:** soft budget of roughly 200 lines per file. When a file
  outgrows it, split by concern and add rows. Grounding reads matched files
  selectively — the sections relevant to the task at hand, not necessarily
  the whole file — so tight, well-headed files route best.

## Personal overlays (in-root only)

- `<name>.local.md` overlays `<name>.md` by filename convention; a
  `.local.md` with no base file is a standalone personal standard.
- Glob-discovered, never indexed (a tracked index cannot list gitignored
  files).
- Ignore mechanism: setup creates `<standards_dir>/.gitignore` containing
  `*.local.md`. That file is setup-owned; no plugin ever edits the
  consumer's root `.gitignore` or any ignore file it did not create.
- **Pre-existing `<standards_dir>/.gitignore`:** a file setup did not
  create is consumer-owned — setup never writes it. Setup verifies it
  covers `*.local.md`; when it does not, setup surfaces the missing line
  and asks the consumer to add it themselves, reporting overlay
  protection as unconfigured until then. Idempotency is unaffected: the
  verify-and-surface path writes nothing on any run.
- Semantics per Layers and precedence: additive/tighten-only; direct
  conflict → team wins; provenance named when a personal rule materially
  shapes output.

## User-global layer

- `~/.claude/standards/` — optional own `README.md` index (same schema,
  same frontmatter key); when absent, degrade to glob discovery of
  `*.md` files there.
- Location fixed in v1; relocation is deferred until a real need appears.
- **Accepted cost:** this location sits outside the working directory, so
  the first read may raise a permission prompt (working-directory reads
  are prompt-free; outside reads are not). Consumers who want it silent
  may allowlist reads of `~/.claude/standards/` in their permission
  settings; skills never treat the prompt (or a denial) as an error —
  a denied user-global read just means that layer contributes nothing.

## Concern file — `.claude/standards.yaml`

```yaml
# committed, team-shared; absent = all defaults
standards_dir: docs/standards
```

- Shape in `standards.schema.json`; every key optional, absent keys mean
  the documented defaults.
- Written by interactive setup only when the consumer relocates the root.
  Skills never write it silently.
- Rationale for a tracked file over plugin `userConfig`: plugin config
  (`pluginConfigs`) is user-settings-only and per-plugin; a team-shared
  value consumed by more than one plugin cannot live there.

## Resolution ladder

The single procedure every consuming skill uses to resolve the team
standards root and its index. Consuming SKILL.md files point here — they
never restate the ladder. **Resolution root:** the git top-level directory
(fall back to the working directory outside a git repo); the concern file
and all repo-relative paths resolve against it.

1. `.claude/standards.yaml` present at the resolution root → use its
   `standards_dir`.
2. Otherwise → default `<standards_dir>` = `docs/standards/`.
3. Index present (`<standards_dir>/README.md` passing the presence test)
   → use it: match task context against `Applies when` clues, load the
   matched files.
4. Index absent → infer from repository context that is NOT auto-loaded:
   docs directories, ecosystem configs, a standards location declared in
   the consumer's `CLAUDE.md` (its ambient content is an inference source
   — auto-loaded surfaces are never re-fetched). On a successful
   inference, OFFER to persist the finding (index bootstrap via setup, or
   the concern file); never write unprompted.
5. Cannot infer, interactive session → ask once, then offer to persist
   the answer.
6. Otherwise → safe ecosystem defaults; nothing persisted. Non-interactive
   contexts skip the ask-and-persist rungs, take this rung, and surface
   the assumption in their output.

No silent writes, ever — every rung that could persist state does so only
by explicit offer and acceptance.

**Personal layers (every rung):** whatever the team rungs above yield,
resolution ALSO discovers the personal layers — glob-discover
`<standards_dir>/*.local.md` overlays, and read `~/.claude/standards/`
(its own index when present, else glob) — and applies them per Layers and
precedence. Matching a team index row never substitutes for this step; a
denied or absent personal layer simply contributes nothing.

**Ambient-content rule:** content already in context (fired `.claude/rules`
directives, auto-loaded `CLAUDE.md`) is never re-pulled by a grounding
step. After compaction or in a fresh task, previously loaded standards do
NOT count as ambient — re-resolve for the task at hand.

**Tolerant reader:** a skill reading an index at an OLDER contract version
than its binding degrades to best-effort routing and surfaces "index at
vX, contract at vY — re-run setup to migrate". A skill reading a NEWER
index also degrades to best-effort routing but says "update the
`<plugin>` plugin" — it never offers migration (no downgrades). No
auto-rewrite in either direction.

## `.claude/rules` seam (division of content)

- **Rules = push** (fire on matching file reads): short imperative
  directives, consumer-owned.
- **Standards = pull** (index-routed at plan/review stages): substantial
  criteria and prose.
- **Pointer pattern:** a path-scoped rule may carry an imperative pointer
  directive to a standards file ("Before editing C#, read
  `docs/standards/csharp.md`") — lazy load on rule fire. Never `@import`
  (imports expand at launch, defeating lazy load), never restated content.
- Setup MAY offer generating pointer rules for indexed ecosystem surfaces
  (interactive only — the `.claude/` write-guard prompt is acceptable
  there).

## Setup and migration (normative)

The single home for the bootstrap procedure. Consuming plugins' setup
skills implement this section by reference; they do not restate it.

**Bootstrap (first run, interactive):**

1. Read state: concern file → index presence test → inference sources
   (existing docs, ecosystem configs, ambient `CLAUDE.md` content).
2. Short-circuit: a conforming index whose `standards-contract` version
   equals the bundled contract version → validate row paths, report
   healthy, exit without interview.
3. A `<standards_dir>/README.md` that fails the presence test is
   hand-authored content: use it as an inference source, and require
   explicit confirmation before converting it into an index. Never
   overwrite it.
4. Interview: confirm the standards root (persist to
   `.claude/standards.yaml` only on relocation), propose surfaces
   inferred from the repository.
5. Write the skeleton: `<standards_dir>/README.md` index with the
   `standards-contract` frontmatter at the bundled contract version, and
   the setup-owned `<standards_dir>/.gitignore` containing `*.local.md`.
6. Validate every index row path (external-row validation duty).
7. Optionally offer pointer-rule generation and an offer (never a demand)
   to reorganize mixed or spread standards content toward the SRP + index
   shape.

**Idempotency:** setup is re-runnable anytime. A re-run against a
conforming, current-version index proposes no changes — run twice, no
diff.

**Migration (inside re-runnable setup — no separate action):** setup
compares the index's `standards-contract` frontmatter to the bundled
contract version. Detection is DIRECTIONAL:

- Index OLDER than the bundled contract → explain the delta and offer
  guided migration. Idempotent: re-run after migration → no diff.
- Index NEWER than the bundled contract → best-effort read, report
  "update the `<plugin>` plugin", and NEVER offer migration — setup
  never downgrades an index, and two plugins at different bundled
  versions must not nag in a loop.

**Ignore-file rule (restated for setup):** the only ignore file setup
touches is the `<standards_dir>/.gitignore` it created itself.

## Versioning

- The contract version lives in this file's `standards-contract`
  frontmatter (the synced binding copy must be self-describing offline);
  `CHANGELOG.md` carries the history.
- Additive schema change → minor; breaking (column, key, or semantics
  change) → major, with a migration note in the changelog and version
  bumps in every consuming plugin.
- A consumer index records its conformance version in its own
  `standards-contract` frontmatter; delta handling is the directional
  migration rule above.
