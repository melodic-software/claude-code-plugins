# Plan: code-metrics audit-duplication fixes

Closes melodic-software/claude-code-plugins#4068.

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

### Goal

**What**: the six audit-duplication fixes the Brief locks, in `plugins/code-metrics` at 0.1.9,
plus one drift-checker change and six registry lines in this repository, in one draft PR that
closes issue 4068.

**Why**: the whole-tree audit hid skipped files behind `complete`, inflated every count by pair
reporting, could not declare this repo's own canonical copies, and left the reader to aggregate
by hand; each number the skill reports has to be one a reader can act on.

### Standards grounding

No `.claude/standards.yaml` and no `docs/standards/README.md` exist, so the ladder's rung 4
applied: inferred from repository conventions not auto-loaded. Offer stands to bootstrap an index
through the planning setup; nothing was written.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| Python | `.claude/rules/ruff-pin.md` (lint only through `scripts/run-ruff.sh check`) | team, path-scoped |
| Skill body | `.claude/rules/skill-bodies-state-current-rules.md` (current rule and reason, no incident narration, `## Next` before `## Gotchas`); `.claude/rules/vendor-docs-are-not-style.md` (house style, `/ai-slop:audit`) | team, path-scoped |
| Shell tests | `docs/conventions/shell-test-helpers/README.md` (per-plugin `pass`/`fail` helpers stay per plugin; repo-tooling suites use `scripts/lib/test-harness.sh`) | team |
| Upstream facts | `docs/conventions/upstream-drift/README.md` (a restated upstream specific carries claim, basis, as-of date, recheck trigger) | team |
| Validation | `AGENTS.md` "Validate a change" (`scripts/affected-tests.sh --run`; a changed file mapping to zero suites is an error) | team, ambient |
| Release | `scripts/check-changelog-parity.sh --check-bump` (a manifest bump must add a `## [<v>]` entry) | team |

### Approach

Five phases, integration slice first. Phase 1 lands the cap machinery end to end (config key to
run row) because it is the only phase that changes what jscpd is asked to scan, and everything
after it measures the same scope. Phase 2 and Phase 3 are file-disjoint and together satisfy the
Brief's headline criterion (one 17-instance `hook-utils.sh` group, excluded once). Phase 4 is the
rendering layer over the shape Phases 2 and 3 produce. Phase 5 is docs and release.

Build technique: kept tracer-bullet slice (Phase 1 runs `audit-duplication.sh --all` on this
repository under both jscpd majors as its runtime probe); no throwaway spike, since the research
already reproduced every tool behavior the design relies on.

### Phase 1: Explicit caps, adapter pre-filter, partial run row [TODO]

Review: code-design

1. Add `duplication.max_lines` (`null`), `duplication.max_size` (`"1mb"`), and
   `duplication.rollup_depth` (`2`) to `scripts/config-defaults.json`; add the three rows to
   `reference/config.md` (the gate `scripts/check-code-metrics-config-reference.py` pins key set
   and default rendering); add the three keys to `skills/setup/templates/config-template.yaml`
   (pinned leaf for leaf by `test_setup_apply.py`).
2. `audit-duplication.sh`: read the two caps beside the existing tunables and export
   `CODE_METRICS_DUP_MAX_LINES` (empty when null) and `CODE_METRICS_DUP_MAX_SIZE`; keep the
   existing three exports byte-identical.
3. `dispatch.sh`: before each `collect`, export `CODE_METRICS_RUN_NOTE_FILE` pointing at
   `$WORK/note.$lane.$measure.$tool`; after a `collect` that exits 0, if that file is non-empty,
   write the run row as `partial` with the file's single line as the reason, else `ok` as today.
   [EXEC-SHAPE] File-per-channel matches how `dispatch.sh` already isolates each adapter's stdout
   and stderr into `$WORK` files.
4. `collectors/jscpd.py`: parse `CODE_METRICS_DUP_MAX_SIZE` with jscpd's own unit grammar
   (`kb`/`mb`/raw bytes) and `CODE_METRICS_DUP_MAX_LINES`; pre-filter the file list by `os.stat`
   size and newline count; pass `--max-size <value>` always and `--max-lines <value or 1000000>`
   always (4.x reads `0` as "use default", so the null cap is spelled as a large explicit number
   [EXEC-SHAPE]); never emit `--max-size 0`; when files were skipped, write one line to the note
   file (`N of M files skipped by duplication.max_size <v> / max_lines <v>; largest: <path>
   (<size>)`); when the pre-filter leaves zero files, write the note and return 0 without invoking
   jscpd (4.x would write no report and the current exit-3 path would call that a failure). Extend
   the `probe` docstring and module docstring: 4.x and 5.x both translate; drop the "jscpd 4 is not
   translated" sentence; record the 5.2.0 `kind` field.
5. `reference/collectors.md`: jscpd row pinned to 5.2.0 with a fresh as-of date and the recheck
   trigger unchanged; add the 4.x maintenance-line fact (`latest-4` = 4.3.0) as a four-part
   verification record.

**Files Affected**

| File | Action | What changes |
|---|---|---|
| `plugins/code-metrics/scripts/config-defaults.json` | Modify | three keys under `duplication` |
| `plugins/code-metrics/reference/config.md` | Modify | three key rows |
| `plugins/code-metrics/skills/setup/templates/config-template.yaml` | Modify | three keys |
| `plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.sh` | Modify | two exports |
| `plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.test.sh` | Modify | export assertions |
| `plugins/code-metrics/scripts/dispatch.sh` | Modify | note-file channel, `partial` row |
| `plugins/code-metrics/scripts/dispatch.test.sh` | Modify | partial-row case via the real jscpd adapter and a stub binary |
| `plugins/code-metrics/scripts/collectors/jscpd.py` | Modify | caps, pre-filter, note file, docstring |
| `plugins/code-metrics/scripts/collectors/test_jscpd.py` | Modify | argv, skip, all-skipped, size-grammar cases |
| `plugins/code-metrics/reference/collectors.md` | Modify | jscpd row, 4.x record |

**Sanity Check:**

- `python3 scripts/check-code-metrics-config-reference.py` exits 0.
- `python3 -m unittest plugins/code-metrics/scripts/collectors/test_jscpd.py` exits 0 and its
  argv-log case asserts `--max-size 1mb` and `--max-lines 1000000` present and `--max-size 0` absent.
- `bash plugins/code-metrics/scripts/dispatch.test.sh` exits 0 with a case whose JSON has
  `run[].status == "partial"` and a reason matching `^[0-9]+ of [0-9]+ files skipped`.
- Runtime probe: with jscpd 5.2.0 on PATH,
  `audit-duplication.sh --json --registry scripts/cross-plugin-source-registry.txt --all | jq '.run[]|select(.lane=="bash")|.status'`
  prints `"ok"` (no file in this repo exceeds 1mb), and the same command with jscpd 4.3.0 on PATH
  prints `"ok"` with `summary.files` equal between the two runs.

### Phase 2: Merge pairs into clone classes [TODO]

Review: code-design

1. New `skills/audit-duplication/scripts/cluster-clones.py` (stdin document, stdout document):
   union-find over rows carrying exactly two `instances[]` whose `collector` reports pairs (rows
   with three or more instances pass through untouched, which covers `dupl` and `cpd`); two rows
   join when they share an instance with identical `(file, start_line, end_line)` and equal
   `values.lines`; the merged row keeps the first row's `values`, the union of instances in
   first-seen order, and appends `clustered` to `labels`. Rows without `instances` pass through.
   Exit 0 on a printed document, 2 on a non-JSON stdin.
2. `audit-duplication.sh`: pipe `report.json` through `cluster-clones.py` before `registry-filter.py`.
3. Fixture: add `scripts/fixtures/sources/cluster/gamma/shared/shared-utils.sh` (byte-identical
   third copy) and a committed capture `scripts/fixtures/tool-output/jscpd-three.json` produced by
   a real jscpd 5.2.0 run over the three copies (two pair rows against `alpha`); the existing
   two-copy capture and every test that replays it stay unchanged.
4. `test_cluster_clones.py`: three copies collapse to one three-instance group counted once;
   overlapping-but-not-identical ranges stay separate; a three-instance input row passes through;
   `summary` is left to `report.py resummarize`.

**Files Affected**

| File | Action | What changes |
|---|---|---|
| `plugins/code-metrics/skills/audit-duplication/scripts/cluster-clones.py` | Create | the post-pass |
| `plugins/code-metrics/skills/audit-duplication/scripts/test_cluster_clones.py` | Create | output-based tests |
| `plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.sh` | Modify | pipeline step |
| `plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.test.sh` | Modify | three-copy case through the stub |
| `plugins/code-metrics/scripts/fixtures/sources/cluster/gamma/shared/shared-utils.sh` | Create | third copy |
| `plugins/code-metrics/scripts/fixtures/tool-output/jscpd-three.json` | Create | capture |

**Sanity Check:**

- `python3 -m unittest plugins/code-metrics/skills/audit-duplication/scripts/test_cluster_clones.py` exits 0.
- `bash plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.test.sh` exits 0
  with a case asserting `summary.clone_groups == 1` and `len(measures[0].instances) == 3` on the
  three-copy capture with no registry.
- `cmp` the three fixture copies: identical.

### Phase 3: Registry cluster lines, drift checker, this repo's six lines [TODO]

Review: code-design

1. `registry-filter.py`: `read_registry` returns, per line, either a single token or a
   `(canonical, [members...])` tuple; `sanctions()` for a cluster line matches each instance's
   repo-relative path against the canonical path or any member via `pathglob.matches`, requires
   distinct carrying directories (the prefix in front of the matched token; the canonical path's
   parent for itself), and records `path` as the line's text. Single-token behavior byte-identical.
   Pre-flight (done in planning): the only other parser of the registry file is
   `scripts/check-cross-plugin-source-drift.sh`; `check-shell-portability.sh` compares whole lines
   to a path-within-plugin and cannot match a multi-token line; every other mention is a comment.
2. `scripts/check-cross-plugin-source-drift.sh`: in the registry load loop, `continue` on a line
   containing whitespace after trimming, with a comment naming the cluster-line grammar and its
   owner (the code-metrics registry filter). `check-cross-plugin-source-drift.test.sh`: a case
   where a multi-token line neither registers nor reports `REGISTRY STALE`.
3. `scripts/cross-plugin-source-registry.txt`: a commented section "Canonical sources outside a
   plugin (cluster lines; read by code-metrics audit-duplication, skipped by the drift checker)"
   with six lines, each mirroring its sync script's `src=` and copy paths:
   `lib/hook-utils.sh plugins/*/hooks/hook-utils.sh`;
   `lib/rewrite-guard.sh plugins/*/hooks/rewrite-guard.sh`;
   `lib/index-regen.sh plugins/*/scripts/index-regen.sh`;
   `lib/resolve-convention-pattern.sh plugins/*/hooks/resolve-convention-pattern.sh`;
   `lib/parse-concern-value.sh plugins/*/skills/*/scripts/parse-concern-value.sh plugins/*/skills/*/scripts/lib/parse-concern-value.sh`;
   `.claude/hooks/hook-telemetry-sink.sh plugins/claude-ops/hooks/hook-telemetry-sink.sh`.
4. Fixture registry `scripts/fixtures/registry/cluster.txt` gains a commented cluster-line example;
   `test_registry_filter.py` gains: cluster line excludes a canonical-plus-copies group; a member
   glob matches; two instances in one carrying directory keep the group; a single-token line still
   excludes exactly as before; `excluded[].path` carries the line text.
5. `reference/config.md` `duplication.registries` row and the SKILL.md configuration paragraph
   describe both line shapes.

**Files Affected**

| File | Action | What changes |
|---|---|---|
| `plugins/code-metrics/skills/audit-duplication/scripts/registry-filter.py` | Modify | cluster grammar |
| `plugins/code-metrics/skills/audit-duplication/scripts/test_registry_filter.py` | Modify | five cases |
| `plugins/code-metrics/scripts/fixtures/registry/cluster.txt` | Modify | example line |
| `scripts/check-cross-plugin-source-drift.sh` | Modify | skip multi-token lines |
| `scripts/check-cross-plugin-source-drift.test.sh` | Modify | one case |
| `scripts/cross-plugin-source-registry.txt` | Modify | six cluster lines |
| `plugins/code-metrics/reference/config.md` | Modify | registries row text |

**Sanity Check:**

- `python3 -m unittest plugins/code-metrics/skills/audit-duplication/scripts/test_registry_filter.py` exits 0.
- `bash scripts/check-cross-plugin-source-drift.sh --check` exits 0 on this tree;
  `bash scripts/check-cross-plugin-source-drift.test.sh` exits 0.
- Runtime probe with jscpd 5.2.0 on PATH:
  `audit-duplication.sh --json --registry scripts/cross-plugin-source-registry.txt --all | jq '[.measures[]|select(any(.instances[]; .file|test("^(lib|\\.claude)/")))]|length'`
  prints `0`, and `jq '[.excluded[]|select(.path|startswith("lib/hook-utils.sh"))]|length'`
  prints `1` with that entry's `instances` length `17`.

### Phase 4: Report sort, rollups, additive summary fields, summary line, no-detector headline [TODO]

Review: code-design

1. `report.py summarize`: when clone-group rows exist, add `by_lane` (lane to `{groups,
   duplicated_lines}`) and `by_directory` (every ancestor directory of each group's first
   instance, cumulative, same shape; keys are repo-relative directory paths, root as `.`).
   `resummarize` inherits it, so the maps are computed over surviving groups after exclusion.
2. `report.py render`: for a document with clone-group rows, sort measures by `values.lines`
   descending then tokens then first instance path (other skills keep today's sort); add a
   `## Rollup` section after Measures with a per-lane table and a per-directory table listing
   directories whose depth is at most `duplication.rollup_depth` (read from `thresholds`/config
   passed as a new `--rollup-depth` argument, default 2); render the summary line as
   `Files with clones: N.` when the document is duplication-shaped (any `instances[]` row or
   `skill == "audit-duplication"`), otherwise today's line byte for byte; when every
   `duplication` run row is `unavailable`, emit one headline under the title naming the first
   adapter's install hint once and `/code-metrics:setup`, and render each lane row's reason with
   the parenthesised hint removed.
3. `reference/report-schema.md`: document `by_lane` and `by_directory` under `summary`; add the
   sentence that readers ignore unknown keys; note "intentional clones" beside "sanctioned
   replication" in the `excluded` row.
4. `test_report.py`: rollup sums equal `duplicated_lines`; cumulative ancestors; depth cut in
   markdown only; sort order; summary line per skill (sibling line unchanged); no-detector headline
   once.

**Files Affected**

| File | Action | What changes |
|---|---|---|
| `plugins/code-metrics/scripts/report.py` | Modify | rollups, sort, summary line, headline |
| `plugins/code-metrics/scripts/test_report.py` | Modify | six cases |
| `plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.sh` | Modify | pass `--rollup-depth` |
| `plugins/code-metrics/reference/report-schema.md` | Modify | fields, ignore-unknown rule, term |

**Sanity Check:**

- `python3 -m unittest plugins/code-metrics/scripts/test_report.py` exits 0.
- `grep -c 'Functions:' <(audit-duplication.sh --all)` prints `0` and
  `grep -c '^Files with clones:' <(audit-duplication.sh --all)` prints `1`; the sibling
  `audit-size.sh --all | tail -3` still contains `Functions:`.
- `audit-duplication.sh --json --all | jq '[.summary.by_lane[].duplicated_lines]|add == .summary.duplicated_lines'` prints `true`.
- With an empty PATH prefix hiding jscpd, `audit-duplication.sh --all | grep -c 'npm install -g jscpd'` prints `1`.

### Phase 5: SKILL.md, README, CHANGELOG, version, dogfood [TODO]

1. `skills/audit-duplication/SKILL.md`: configuration section names the three new keys and both
   registry line shapes; "Run it" gains the no-detector instruction (offer the install command to
   the user, run it only on confirmation, never silently); "Reading the numbers" states clone
   classes, the `partial` row, and the rollup; `## Next` kept before `## Gotchas`; the gotcha
   about pairs is rewritten to state clusters. Prose stays in house style (`/ai-slop:audit` on the
   file).
2. `README.md`: the audit-duplication row mentions rollups and the cluster line; the known-gaps
   bullet's list of prose-restated defaults is checked against what SKILL.md now restates.
3. `CHANGELOG.md`: `## [0.1.9]` with Added / Changed / Fixed entries, one per Brief item;
   `.claude-plugin/plugin.json` version 0.1.9.
4. Dogfood: `scripts/affected-tests.sh --run` over the whole diff; `scripts/run-ruff.sh check`
   over the changed Python; `shellcheck` and `shfmt -d` over changed shell; both jscpd majors'
   whole-tree runs recorded as distilled numbers in this file's Phase 5 notes (surviving groups,
   duplicated lines, exclusions) with no memory-slice paths.

**Files Affected**

| File | Action | What changes |
|---|---|---|
| `plugins/code-metrics/skills/audit-duplication/SKILL.md` | Modify | config, run-it, reading, gotchas |
| `plugins/code-metrics/README.md` | Modify | row, known gaps |
| `plugins/code-metrics/CHANGELOG.md` | Modify | `[0.1.9]` |
| `plugins/code-metrics/.claude-plugin/plugin.json` | Modify | version |

**Sanity Check:**

- `jq -r .version plugins/code-metrics/.claude-plugin/plugin.json` prints `0.1.9`;
  `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.
- `scripts/affected-tests.sh --run` exits 0; `scripts/run-ruff.sh check plugins/code-metrics` exits 0.
- `grep -n '^## Next' plugins/code-metrics/skills/audit-duplication/SKILL.md` precedes `^## Gotchas`.
- `markdownlint-cli2` over the changed markdown exits 0.

### Alternatives Considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Detect skips as files-passed minus `statistics.total.sources` | contradicted: `sources` counts token sources that reached detection, reproduced on 4.3.0 and 5.2.0 | jscpd adds a per-file skip list to its JSON report |
| Keep jscpd's per-major defaults, detect only | jscpd 4.x users silently lose every file over 1000 lines | jscpd 4.x line reaches end of life |
| Merge pairs inside the jscpd adapter | a second pair-reporting collector would need it again; the rule is about the report | no other collector ever reports pairs and the post-pass is the only consumer |
| A second registry file for cluster lines | two registries for one concept; the plugin's docs already name this file as the shape | a second reader of the registry file cannot be taught to skip cluster lines |
| `by_directory` as direct-parent rows | no documented precedent; a plugin's files would never roll up to the plugin | a consumer needs non-overlapping per-directory sums |
| Stderr prefix as the adapter-to-dispatcher channel | `dispatch.sh` reads stderr only on failure and truncates it; a note file is unambiguous and output-testable | the adapter contract grows a structured stderr protocol for other reasons |

### Test Strategy

Output-based tests drive every script at its command line with fixture inputs and assert on the
printed document, per the TDD principles skill's decision order (output first, state second,
communication last). jscpd is the one unmanaged out-of-process dependency and stays stubbed by a
fake binary that replays a committed capture; nothing in-process is mocked: `cluster-clones.py`,
`registry-filter.py`, and `report.py` are driven for real by `audit-duplication.test.sh` and
`dispatch.test.sh`. One communication-based assertion exists because the boundary is the tool's
argv: `test_jscpd.py`'s existing `argv_log` stub asserts the explicit caps. Red first: each phase
writes its failing test against the named boundary, then the change.

Test boundaries (all existing unless marked): `jscpd.py collect` argv and note-file output
(existing CLI, new env vars); `dispatch.sh` run rows (existing); `cluster-clones.py` stdin/stdout
(new script, same document contract as `registry-filter.py`); `registry-filter.py --registry`
(existing); `report.py summarize|resummarize|render` (existing, new `--rollup-depth` argument);
`audit-duplication.sh --json` (existing); `check-cross-plugin-source-drift.sh --check` (existing).
A boundary implementation picks that this list does not name is a deviation logged to
`DEVIATIONS.md` beside this file.

Edge cases named in the Brief's criteria: overlapping-but-not-identical ranges; two copies in one
directory; all files skipped; no registry configured; a lane whose collector never resolved.
Existing tests updated: `audit-duplication.test.sh` (export assertions, three-copy case),
`test_jscpd.py` (argv), `check-cross-plugin-source-drift.test.sh` (skip case),
`test_setup_apply.py` passes unchanged once the template carries the keys.

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| jscpd 4.x argv differs from 5.x for a passed cap | Low | Med | both majors verified this session (`--max-lines`, `--max-size` share names and short forms); Phase 1's runtime probe runs both |
| A multi-token registry line breaks a reader not found in pre-flight | Low | High | pre-flight grepped all 12 mentions; the drift-checker test case is the guard; `scripts/affected-tests.sh` selects every suite referencing the registry |
| `by_directory` on a large monorepo makes the JSON heavy | Low | Low | the map holds only directories that contain a group; markdown cuts at depth 2 |
| Union-find merges two genuinely different clones that share one instance | Low | Med | the key requires identical range and equal `lines`, so only the same fragment joins |
| The sort change alters other skills' markdown | Low | Med | sort branch is gated on clone rows; `test_report.py` asserts a size document renders byte-identically |
| Version bump without changelog entry fails CI | Low | Low | Phase 5 sanity check runs the parity gate |
