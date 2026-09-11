# Plan: code-metrics audit-duplication fixes

Issue: to be filed once the Brief is confirmed; this line then reads `Closes #<n>`.

## Brief

### TLDR

- `audit-duplication` reports skipped files instead of hiding them: the jscpd adapter pre-filters
  by byte size and line count, passes both caps explicitly on 4.x and 5.x, and marks the lane
  `partial` when anything was skipped; defaults are no line cap and a 1mb byte cap.
- jscpd's pair reports are merged into clone classes before summarizing, so N copies count once.
- The sanctioned-replication registry gains multi-token lines (`<canonical path> <copy path or glob>...`)
  so a canonical file outside any plugin can declare its copies; this repo's drift checker skips
  those lines and six such lines are added here.
- The markdown report sorts clone rows by duplicated lines, adds per-lane and per-directory rollups
  (cumulative, counts beside share, computed after exclusion, listed to depth 2), and the JSON gains
  `summary.by_lane` / `summary.by_directory` as additive `v1` fields with an explicit ignore-unknown
  rule in the schema reference.
- The duplication summary line drops "Functions" and "Over reference"; a run with no detector prints
  one consolidated install headline and the skill offers, never performs, the install. Version 0.1.9.

### Goal

A whole-tree or change-scoped duplication audit on any repository, this one included, produces
numbers a reader can act on without re-aggregating: no file is silently dropped by a size cap, a
fragment copied N times is one group counted once, replication the repository declares about itself
(including copies of a root-level canonical file) is excluded and shown as an exclusion, and the
report says where the surviving duplication sits by lane and by directory. On this repository the
audit reads clean apart from genuine duplication.

### Constraints

- The plugin never installs, downloads, or `npx`-fetches a detector; SKILL.md may instruct Claude to
  offer the install command and run it only on the user's confirmation.
- The report emits no finding, severity, or exit-code gate; duplication has no reference value.
- The `code-metrics/v1` schema string is unchanged; every JSON change is additive (new optional
  fields), and `reference/report-schema.md` states that readers ignore unknown keys.
- Single-token registry lines keep their exact meaning; the drift checker
  (`scripts/check-cross-plugin-source-drift.sh`) keeps its behavior for them and skips multi-token
  lines.
- Both jscpd 4.x (`latest-4` = 4.3.0) and 5.x (5.2.0) stay supported by the adapter; the adapter
  always passes explicit `--max-lines` and `--max-size` on 4.x (its `0` means "default" for lines and
  "skip all" for size) and never emits `--max-size 0`.
- An unmeasured value is `null`, never `0`; a run that measured nothing keeps "Measured nothing".
- Validate with `scripts/affected-tests.sh --run`; every changed file maps to at least one suite.
- No `lib/hook-utils.sh` or other cross-plugin synced source is edited; registry lines mirror the
  `src=` each `scripts/sync-*.sh` already declares.
- One issue, one draft PR whose body opens with `Closes #<issue>` and carries the four required
  sections; CHANGELOG entry under `[0.1.9]`.

### Acceptance criteria

- Running `audit-duplication.sh --all` on this repository with jscpd 4.3.0 and again with 5.2.0
  reports identical clone groups for files under 1mb, and the run table's bash row reads `partial`
  naming the count and largest of any files the adapter's pre-filter skipped; with the shipped
  defaults no file in this repository is skipped.
- `duplication.max_lines` defaults to `null` (no cap) and `duplication.max_size` to `1mb`; both are
  documented in `reference/config.md` (gated against `config-defaults.json`) and exported to the
  adapter, and the adapter's tests cover the 4.x explicit-cap translation and the never-`0` rule.
- IF every file in a lane is skipped by the caps, THEN that lane's run row reads `partial` with the
  reason, no collector is invoked for it, and the script never exits 3 for that cause.
- Seventeen identical copies of `hook-utils.sh` (root `lib/` plus sixteen plugins) produce exactly
  one clone group with seventeen instances, and with the registry line
  `lib/hook-utils.sh plugins/*/hooks/hook-utils.sh` that group appears once under `excluded[]`
  with `duplicated_lines` counted once, not sixteen times.
- Two groups whose instances overlap without identical line ranges (the `hook-telemetry-sink.sh`
  shape) stay separate groups after the merge.
- A multi-token registry line excludes a group only when every instance matches the canonical path
  or one of the copy paths or globs and the instances sit in distinct carrying directories; two copies
  inside one directory still count as duplication; a single-token line behaves exactly as before
  (existing registry tests unchanged and passing).
- `scripts/check-cross-plugin-source-drift.sh --check` passes on this repository with the six new
  multi-token lines present, and its tests cover a multi-token line being skipped.
- After this change, `audit-duplication.sh --registry scripts/cross-plugin-source-registry.txt --all`
  on this repository reports zero surviving groups whose instances include a file under root `lib/`
  or `.claude/hooks/`.
- WHILE no registry is configured and none is passed, the report's `excluded[]` is empty and the
  summary line says so.
- The markdown Measures table for a duplication document lists clone groups in descending order of
  duplicated lines, and the report carries a `## Rollup` section with a per-lane table and a
  per-directory table (rows to depth 2 by default, `duplication.rollup_depth` configurable) whose
  numbers are cumulative up the tree, carry `groups` and `duplicated_lines`, and sum consistently
  with `summary.duplicated_lines` after exclusion.
- The JSON `summary` carries `by_lane` and `by_directory` with the same numbers; `schema` is still
  `code-metrics/v1`; `reference/report-schema.md` documents both fields and states that readers
  ignore unknown keys; `verification:measure`'s consumption is unaffected.
- The duplication summary line reads `Files with clones: N.` followed by the duplicated-lines and
  exclusion lines, with no "Functions" or "Over reference" text; the sibling skills' summary lines are
  byte-identical to today's.
- When no duplication collector resolves, the markdown opens with one headline naming the install
  command and `/code-metrics:setup`, the per-lane rows no longer repeat the install hint, and
  SKILL.md instructs Claude to offer the install and run it only on confirmation.
- The jscpd adapter's docstring and `reference/collectors.md` state that 4.x and 5.x are both
  translated, pin 5.2.0, and note the `kind` field; the schema reference names "intentional clones"
  beside "sanctioned replication".
- `plugin.json` reads 0.1.9 and `CHANGELOG.md` carries a `[0.1.9]` entry covering every item above;
  `scripts/affected-tests.sh --run` passes.

### Captured assumptions

- Version bumps to 0.1.9, not 0.2.0, because this plugin's changelog bumps patch for features
  (0.1.7 was a `feat`). Revisit if the marketplace's release convention says a new registry grammar
  or JSON fields require a minor bump.
- Once-per-class counting follows PMD CPD and SonarQube; the fetched literature is silent on how
  duplicated lines are totalled, and jscpd v5 is the one tool that sums per pair. Revisit if a
  standard sets a duplicated-lines definition.
- The merge keys on identical (file, start_line, end_line) instances and equal `lines`; closure is
  exact only for type-1/type-2 clones, which is all the adapter receives today because it passes no
  `--max-gap-lines`. Revisit if `similar` clones are ever enabled.
- `rollup_depth` default 2 is the plugin's choice; no upstream sets a depth (SonarQube and Codacy
  roll up every directory). Revisit if a consuming repository's layout makes depth 2 meaningless.
- The byte cap of 1mb aligns with jscpd 5.0.7's parser guard and SonarJS's 1000kb generated-code
  rule; no line cap by default aligns with jscpd 5, PMD CPD, SonarQube, and Linguist. Revisit if
  jscpd changes its default in a later major.
- The cluster lines live in the existing registry file because the plugin's own documentation names
  that file as the shape; this is a repository-convention choice with no external authority.
  Revisit if the drift checker grows a second consumer of the file.
- "Sanctioned replication" stays the plugin's term; the literature's term "intentional clones"
  (Cordy 2008) is named beside it. No upstream tool models the canonical-plus-copies relation, so
  no vocabulary conflict exists.
- The upstream doc drift found in jscpd (`docs/rust.md` "no limit" for `--max-size`, "per block"
  help text for `--max-lines`, stale jscpd.dev v5 defaults) is reported separately, not here.

### Out-of-scope

- Installing a detector on the user's behalf, or an `npx` fallback.
- A pass/fail gate, threshold, or severity for duplication.
- Cross-language clone detection.
- Changing `dupl` or `cpd` adapters beyond passing their rows through the new merge and rollup
  steps unchanged.
- A second registry file or a manifest generated from the sync scripts.
- Migrating the registry's single-token lines to the new grammar.

### Deferred questions

- None. Every question registered in the interview was answered; no row was deferred or blocked.

## Plan

<empty — populated by /planning:plan>
