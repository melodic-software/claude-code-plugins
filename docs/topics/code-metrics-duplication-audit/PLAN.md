# Plan: code-metrics audit-duplication fixes

Closes melodic-software/claude-code-plugins#4068.

## Brief

Scope-change note (2026-09-11, before approval, from the fresh-context plan review and the
stress-test, each finding verified against the tree): four criteria below were corrected. The
`hook-utils.sh` class has eighteen instances (root plus seventeen plugins), not seventeen. The
shipped 1mb cap skips one tracked file here, `plugins/miro/dist/index.min.js` (1.45mb), so the
typescript lane reads `partial` by design. The `hook-telemetry-sink.sh` pair differs at line 51
and has no sync script, so it is not sanctioned replication and its registry line is dropped
(five lines, not six). Pair-to-class merging joins byte-aligned copies; a copy embedded at a
different offset with different surrounding lines stays its own group. Cluster lines carry an
explicit `->` marker because a registered path may contain a space.

### TLDR

- `audit-duplication` reports skipped files instead of hiding them: the jscpd adapter pre-filters
  by byte size and line count, passes both caps explicitly on 4.x and 5.x, and marks the lane
  `partial` when anything was skipped; defaults are no line cap and a 1mb byte cap.
- jscpd's pair reports are merged into clone classes before summarizing, so byte-aligned copies
  count once.
- The sanctioned-replication registry gains cluster lines
  (`<canonical path> -> <copy path or glob>...`) so a canonical file outside any plugin can declare
  its copies; this repo's drift checker skips marked lines and five such lines are added here.
- The markdown report sorts clone rows by duplicated lines, adds per-lane and per-directory rollups
  (cumulative, counts beside share, computed after exclusion, listed to depth 2), and the JSON gains
  `summary.by_lane` / `summary.by_directory` as additive `v1` fields with an explicit ignore-unknown
  rule in the schema reference.
- The duplication summary line drops "Functions" and "Over reference"; a run with no detector prints
  one consolidated install headline and the skill offers, never performs, the install. Version 0.1.9.

### Goal

A whole-tree or change-scoped duplication audit on any repository, this one included, produces
numbers a reader can act on without re-aggregating: no file is silently dropped by a size cap,
byte-aligned copies of a fragment form one group counted once, replication the repository declares
about itself (including copies of a root-level canonical file) is excluded and shown as an
exclusion, and the report says where the surviving duplication sits by lane and by directory. On
this repository the audit reads clean apart from genuine duplication.

### Constraints

- The plugin never installs, downloads, or `npx`-fetches a detector; SKILL.md may instruct Claude to
  offer the install command and run it only on the user's confirmation.
- The report emits no finding, severity, or exit-code gate; duplication has no reference value.
- The `code-metrics/v1` schema string is unchanged; every JSON change is additive (new optional
  fields), and `reference/report-schema.md` states that readers ignore unknown keys.
- Single-token registry lines keep their exact meaning, including a path that contains a space;
  the drift checker (`scripts/check-cross-plugin-source-drift.sh`) keeps its behavior for them and
  skips only lines carrying the `->` marker.
- Both jscpd 4.x (`latest-4` = 4.3.0) and 5.x (5.2.0) stay supported by the adapter; the adapter
  always passes explicit `--max-lines` and `--max-size` on both majors, treats a configured `0` as
  `null` (jscpd reads `0` as "default" for 4.x lines and "skip all" everywhere else), and never
  emits a `0` cap.
- An unmeasured value is `null`, never `0`; a run that measured nothing keeps "Measured nothing".
- Validate with `scripts/affected-tests.sh --run`; every changed file maps to at least one suite.
- No `lib/hook-utils.sh` or other cross-plugin synced source is edited; every cluster line mirrors
  the `src=` and copy list its `scripts/sync-*.sh` already declares.
- One issue, one draft PR whose body opens with `Closes #<issue>` and carries the four required
  sections; CHANGELOG entry under `[0.1.9]`.

### Acceptance criteria

- Running `audit-duplication.sh --json --all` on this repository with jscpd 4.3.0 and again with
  5.2.0 yields, for every byte-identical whole-file class, the same set of instances (file and
  line range) per group; `tokens` and instance order are excluded from the comparison because the
  two majors tokenize differently and hub on different copies. The bash row reads `ok` under both;
  the typescript row reads `partial` under both, naming `plugins/miro/dist/index.min.js` as the one
  file over the 1mb cap.
- `duplication.max_lines` defaults to `null` (no cap) and `duplication.max_size` to `1mb`; both are
  documented in `reference/config.md` (gated against `config-defaults.json`) and exported to the
  adapter, and the adapter's tests cover the explicit-cap argv on both majors, the `0`-means-null
  rule, and that no `0` cap is ever passed.
- IF every file in a lane is skipped by the caps, THEN that lane's run row reads `partial` with the
  reason, no collector is invoked for it, and the script never exits 3 for that cause.
- The eighteen byte-identical copies of `hook-utils.sh` (root `lib/` plus the seventeen plugin
  copies `scripts/sync-hook-utils.sh --print-manifest` lists) produce exactly one clone group with
  eighteen instances, and with the registry line
  `lib/hook-utils.sh -> plugins/*/hooks/hook-utils.sh` that group appears once under `excluded[]`
  with `duplicated_lines` counted once.
- Two groups whose instances overlap without identical line ranges (the `hook-telemetry-sink.sh`
  shape, and three copies of one fragment embedded at different offsets) stay separate groups after
  the merge.
- A cluster line excludes a group only when every instance's root-relative path matches the
  canonical path or one of the members (literal or glob) and the instances' directories are all
  distinct; two copies inside one directory still count as duplication; a single-token line behaves
  exactly as before, a registered path containing a space included; when a single-token line and a
  cluster line both match, the first matching line in file order wins.
- `scripts/check-cross-plugin-source-drift.sh --check` passes on this repository with the five new
  cluster lines present, each under its own annotation block, and its tests cover a marked line
  being skipped.
- After this change, `audit-duplication.sh --json --registry scripts/cross-plugin-source-registry.txt --all`
  on this repository reports zero surviving groups whose instances include a file under root `lib/`,
  from the repository root and from a subdirectory alike.
- WHILE no registry is configured and none is passed, the report's `excluded[]` is empty and the
  summary states that no registry was configured.
- The markdown Measures table for a duplication document lists clone groups in descending order of
  duplicated lines, and the report carries a `## Rollup` section with a per-lane table and a
  per-directory table (rows to depth 2 by default, `duplication.rollup_depth` configurable) whose
  numbers are cumulative up the tree and carry `groups` and `duplicated_lines`; the per-lane
  values sum to `summary.duplicated_lines`, and the root row of `by_directory` equals it.
- The JSON `summary` carries `by_lane` and `by_directory` with the same numbers (empty maps when a
  duplication collector ran and found nothing); `schema` is still `code-metrics/v1`;
  `reference/report-schema.md` documents both fields, the run row's additive `hint` field, and
  states that readers ignore unknown keys; `verification:measure`, the one marketplace consumer,
  reads only `status` and is unaffected.
- The duplication summary line reads `Files with clones: N.` followed by the duplicated-lines and
  exclusion lines, with no "Functions" or "Over reference" text; the sibling skills' summary lines are
  byte-identical to today's.
- When no duplication collector resolves, the markdown opens with one headline naming the install
  command and `/code-metrics:setup`, taken from the run row's `hint` field rather than parsed out of
  its reason, and SKILL.md instructs Claude to offer the install and run it only on confirmation.
- The jscpd adapter's docstring and `reference/collectors.md` state that 4.x and 5.x are both
  translated, pin 5.2.0, note the `kind` field, and record that the two majors tokenize differently;
  the schema reference names "intentional clones" beside "sanctioned replication".
- `plugin.json` reads 0.1.9 and `CHANGELOG.md` carries a `[0.1.9]` entry covering every item above;
  `scripts/affected-tests.sh --run` exits 0, or exits 3 with only Python suites listed as not run,
  each of which then passes under pytest.

### Captured assumptions

- Version bumps to 0.1.9, not 0.2.0, because this plugin's changelog bumps patch for features
  (0.1.7 was a `feat`). Revisit if the marketplace's release convention says a new registry grammar
  or JSON fields require a minor bump.
- Once-per-class counting follows PMD CPD and SonarQube; the fetched literature is silent on how
  duplicated lines are totalled, and jscpd v5 is the one tool that sums per pair. Revisit if a
  standard sets a duplicated-lines definition.
- The merge keys on identical (file, start_line, end_line) instances and equal `lines`, so only
  byte-aligned copies join; jscpd extends a clone greedily into shared flanking lines, so offset
  copies get ranges differing by a line and stay separate on both majors. Closure is exact only for
  type-1/type-2 clones, which is all the adapter receives because it passes no `--max-gap-lines`.
  Revisit if `similar` clones are ever enabled.
- Merged instances are sorted by path so the first instance, and therefore `by_directory`
  attribution, is the same under 4.x (which hubs on the last input) and 5.x (which hubs on the first).
- `rollup_depth` default 2 is the plugin's choice; no upstream sets a depth (SonarQube and Codacy
  roll up every directory). Revisit if a consuming repository's layout makes depth 2 meaningless.
- The byte cap of 1mb aligns with jscpd 5.0.7's parser guard and SonarJS's 1000kb generated-code
  rule, and means 1,048,576 bytes, the value jscpd 5.2.0 reports for `1mb`; no line cap by default
  aligns with jscpd 5, PMD CPD, SonarQube, and Linguist. Revisit if jscpd changes its default or
  multiplier in a later major.
- The cluster lines live in the existing registry file because the plugin's own documentation names
  that file as the shape; this is a repository-convention choice with no external authority.
  Revisit if the drift checker grows a second consumer of the file.
- The `->` marker is the cluster-line signal because a registered single-token path may contain a
  space and the drift checker's tests protect that case. Revisit if a consuming repository has a
  path containing ` -> `.
- The `.claude/hooks/hook-telemetry-sink.sh` and `plugins/claude-ops/hooks/hook-telemetry-sink.sh`
  pair differs at line 51 and has no sync script, so the audit keeps reporting its overlap as
  duplication; a future sync script earns it a cluster line. Revisit when that script exists.
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
- A repository config excluding `plugins/miro/dist/` from this repo's own audits; the `partial`
  row is the designed reading and a config is the consuming repo's choice.

### Deferred questions

- None. Every question registered in the interview was answered; no row was deferred or blocked.

## Plan

### Goal

**What**: the six audit-duplication fixes the Brief locks, in `plugins/code-metrics` at 0.1.9,
plus one drift-checker change and five registry cluster lines in this repository, in one draft PR
that closes issue 4068.

**Why**: the whole-tree audit hid skipped files behind `complete`, inflated every count by pair
reporting, could not declare this repo's own canonical copies, and left the reader to aggregate
by hand; each number the skill reports has to be one a reader can act on.

### Standards grounding

No `.claude/standards.yaml` and no `docs/standards/README.md` exist, so the ladder's rung 4
applied: inferred from repository conventions not auto-loaded. The offer to bootstrap an index
through the planning setup stands; nothing was written.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| Python | `.claude/rules/ruff-pin.md` (lint only through `scripts/run-ruff.sh check`) | team, path-scoped |
| Skill body | `.claude/rules/skill-bodies-state-current-rules.md` (current rule and reason, no incident narration, `## Next` before `## Gotchas`); `.claude/rules/vendor-docs-are-not-style.md` (house style, `/ai-slop:audit`) | team, path-scoped |
| Shell tests | `docs/conventions/shell-test-helpers/README.md` (per-plugin `pass`/`fail` helpers stay per plugin; repo-tooling suites use `scripts/lib/test-harness.sh`) | team |
| Upstream facts | `docs/conventions/upstream-drift/README.md` (a restated upstream specific carries claim, basis, as-of date, recheck trigger) | team |
| Validation | `AGENTS.md` "Validate a change" (`scripts/affected-tests.sh --run`; exit 3 lists suites in ecosystems it cannot run) | team, ambient |
| Release | `scripts/check-changelog-parity.sh --check-bump` (a manifest bump must add a `## [<v>]` entry) | team |

### Approach

Five phases, integration slice first. Phase 1 lands the cap machinery end to end (config key to
run row) because it is the only phase that changes what jscpd is asked to scan. Phases 2 and 3
together satisfy the headline criterion (one eighteen-instance `hook-utils.sh` group, excluded
once). Phase 4 is the rendering layer over the shape Phases 2 and 3 produce. Phase 5 is docs and
release. Phase 3 is committed on its own because editing the registry fans the CI test selection
out to most of the corpus, and a red there should bisect to one commit.

Build technique: kept tracer-bullet slice (Phase 1's runtime probe runs the audit on this
repository under both jscpd majors); no throwaway spike, since the research and the stress-test
already reproduced every tool behavior the design relies on.

Pre-flight results (done during planning, recorded so no phase repeats them): the registry file is
named in twelve files; only `scripts/check-cross-plugin-source-drift.sh` parses it into a lookup,
`scripts/check-shell-portability.sh` compares whole lines to a path-within-plugin and cannot match
a marked line, every other mention is a comment. No script outside `plugins/code-metrics/` reads
`code-metrics/v1` documents; `verification:measure` reads `status` only.

Tool provisioning for probes: jscpd is never installed by the plugin, but the runtime probes and
the fixture captures need both majors. A session runs
`npm install --prefix <scratch>/jscpd4 jscpd@4.3.0` and `npm install --prefix <scratch>/jscpd5 jscpd@5.2.0`
into two scratch prefixes outside the repository and prepends the wanted `node_modules/.bin` to
`PATH` per probe. A probe whose major is absent prints `SKIP` and is not a failure, the way
`audit-duplication.test.sh`'s real-cluster case already does.

### Phase 1: Explicit caps, adapter pre-filter, partial run row [TODO]

Review: code-design

1. Add `duplication.max_lines` (`null`), `duplication.max_size` (`"1mb"`), and
   `duplication.rollup_depth` (`2`) to `scripts/config-defaults.json`; add the three rows to
   `reference/config.md` (gated by `scripts/check-code-metrics-config-reference.py`), with the
   note that a `0` cap means `null` and that CRLF checkouts count one extra byte per line; add the
   three keys to `skills/setup/templates/config-template.yaml` (pinned by `test_setup_apply.py`).
2. `audit-duplication.sh`: read the caps beside the existing tunables, map `0` to null, and export
   `CODE_METRICS_DUP_MAX_LINES` (empty when null) and `CODE_METRICS_DUP_MAX_SIZE`; keep the
   existing three exports byte-identical.
3. `dispatch.sh`: before each `collect`, export `CODE_METRICS_PARTIAL_REASON_FILE` pointing at
   `$WORK/partial.$lane.$measure.$tool` (the work dir is a fresh `mktemp -d` per run and one tool
   runs per lane, so no stale file exists); after a `collect` that exits 0, if that file is
   non-empty, write the run row as `partial` with the file's single line as the reason, else `ok`
   as today. On a failed probe, also write the adapter's install hint into an additive `hint`
   field on the run row (`null` otherwise) and keep `reason` as it is built today.
   [EXEC-SHAPE] File-per-channel matches how `dispatch.sh` already isolates each adapter's stdout
   and stderr into `$WORK` files.
4. `collectors/jscpd.py`: parse `CODE_METRICS_DUP_MAX_SIZE` with the multipliers jscpd uses
   (`kb` = 1024, `mb` = 1,048,576, bare digits = bytes) and `CODE_METRICS_DUP_MAX_LINES`; treat an
   empty or `0` value as no cap; pre-filter the file list by `os.stat` size and, only when a line
   cap is set, by a binary-mode newline count; pass `--max-size <bound + 1 bytes>` always and
   `--max-lines <bound + 1, or 1000000 when null>` always, so the pre-filter is the only gate on both
   majors [EXEC-SHAPE] (4.x reads `--max-lines 0` as "use the 1000 default" and both majors read a
   `0` size as "skip all"); when files were skipped, write one line to the partial-reason file
   (`N of M files skipped by duplication.max_size <v> / max_lines <v>; largest: <path> (<bytes>)`),
   or to stderr when the variable is unset (direct runs) or the path is unwritable, never failing
   for that; when the pre-filter leaves zero files, write the note and return 0 without invoking
   jscpd (4.x would write no report and the current exit-3 path would call that a failure). Extend
   the module docstring: 4.x and 5.x both translate; drop the "jscpd 4 is not translated"
   sentence; record the 5.2.0 `kind` field and that the majors tokenize differently.
5. `registry-filter.py --zero-floor`: a `partial` duplication row counts as measured, so an
   all-excluded or clone-free lane that skipped a file still states `duplicated_lines: 0` and
   `clone_groups: 0`.
6. `reference/collectors.md`: jscpd row pinned to 5.2.0 with a fresh as-of date; add four-part
   verification records for the 4.x maintenance line (`latest-4` = 4.3.0), the `1mb` multiplier,
   and the token-count difference between majors.

**Files Affected**

| File | Action | What changes |
|---|---|---|
| `plugins/code-metrics/scripts/config-defaults.json` | Modify | three keys under `duplication` |
| `plugins/code-metrics/reference/config.md` | Modify | three key rows, `0`-means-null and CRLF notes |
| `plugins/code-metrics/skills/setup/templates/config-template.yaml` | Modify | three keys |
| `plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.sh` | Modify | two exports, `0` to null |
| `plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.test.sh` | Modify | export assertions; its `5.1.2` stub version string becomes `5.2.0` |
| `plugins/code-metrics/scripts/dispatch.sh` | Modify | partial-reason channel, `partial` row, `hint` field |
| `plugins/code-metrics/scripts/dispatch.test.sh` | Modify | partial-row case: sets `CODE_METRICS_DUP_MAX_SIZE` to a small value itself (dispatch never exports caps) and adds a jscpd stub beside the existing scc stub; a `hint` assertion on a failed probe |
| `plugins/code-metrics/scripts/collectors/jscpd.py` | Modify | caps, pre-filter, note, docstring |
| `plugins/code-metrics/scripts/collectors/test_jscpd.py` | Modify | argv on both stub versions, skip, all-skipped, size grammar, `0`, unset variable; docstring version |
| `plugins/code-metrics/skills/audit-duplication/scripts/registry-filter.py` | Modify | zero floor counts `partial` |
| `plugins/code-metrics/skills/audit-duplication/scripts/test_registry_filter.py` | Modify | zero-floor `partial` case |
| `plugins/code-metrics/reference/collectors.md` | Modify | jscpd row, three verification records |

**Sanity Check:**

- `python3 scripts/check-code-metrics-config-reference.py` exits 0;
  `python3 -m unittest plugins/code-metrics/skills/setup/scripts/test_setup_apply.py` exits 0.
- `python3 -m unittest plugins/code-metrics/scripts/collectors/test_jscpd.py` exits 0; its argv-log
  case asserts `--max-size 1048577` and `--max-lines 1000000` present and no argument equal to `0`
  follows either flag.
- `bash plugins/code-metrics/scripts/dispatch.test.sh` exits 0 with a case whose JSON has a run row
  `status == "partial"` and a reason matching `^[0-9]+ of [0-9]+ files skipped`, and a case whose
  failed-probe row carries a non-null `hint`.
- `python3 -m unittest plugins/code-metrics/skills/audit-duplication/scripts/test_registry_filter.py`
  exits 0 with the zero-floor `partial` case.
- Runtime probe (SKIP when a major is absent): with jscpd 5.2.0 on PATH,
  `audit-duplication.sh --json --all | jq -c '[.run[]|select(.measure=="duplication")|{lane,status}]'`
  shows `bash` `ok` and `typescript` `partial`, and the typescript reason names
  `plugins/miro/dist/index.min.js`; the same under 4.3.0.

### Phase 2: Merge pairs into clone classes [TODO]

Review: code-design

1. New `skills/audit-duplication/scripts/cluster-clones.py` (stdin document, stdout document):
   union-find over every row with exactly two `instances[]`, whatever its `collector` (a
   three-or-more-instance row is already a class and passes through); two rows join when they
   share an instance with identical `(file, start_line, end_line)` and equal `values.lines`; the
   merged row keeps the first row's `values`, the union of instances sorted by `(file,
   start_line)`, and appends `clustered` to `labels`. Rows without `instances` pass through. Exit 0
   on a printed document, 2 on a non-JSON stdin.
2. `audit-duplication.sh`: pipe `report.json` through `cluster-clones.py` before `registry-filter.py`.
3. Fixtures, outside `fixtures/sources` so no suite that scopes that tree changes its counts:
   `scripts/fixtures/clone-classes/aligned/{a,b,c}/shared/shared-utils.sh` (three byte-identical
   copies) and `scripts/fixtures/clone-classes/offset/{c1,c2,c3}.sh` (one 41-line fragment at
   offsets 1, 2, 3 with different flanking lines); committed captures
   `scripts/fixtures/tool-output/jscpd-aligned3.json` and `jscpd-offset3.json` produced by a real
   jscpd 5.2.0 run, then rewritten to repo-relative names (the adapter passes `--absolute`, so the
   raw capture carries machine paths, and the stub replays the file regardless of input).
4. `test_cluster_clones.py`: aligned three copies collapse to one three-instance group with
   `lines` counted once; offset copies stay two groups; a three-instance input row passes
   through; a two-instance `cpd`-labelled row joins when it shares an identical instance; merged
   instance order is by path; `summary` is left to `report.py resummarize`.

**Files Affected**

| File | Action | What changes |
|---|---|---|
| `plugins/code-metrics/skills/audit-duplication/scripts/cluster-clones.py` | Create | the post-pass |
| `plugins/code-metrics/skills/audit-duplication/scripts/test_cluster_clones.py` | Create | output-based tests |
| `plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.sh` | Modify | pipeline step |
| `plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.test.sh` | Modify | aligned and offset cases through the stub |
| `plugins/code-metrics/scripts/fixtures/clone-classes/aligned/{a,b,c}/shared/shared-utils.sh` | Create | three copies |
| `plugins/code-metrics/scripts/fixtures/clone-classes/offset/{c1,c2,c3}.sh` | Create | offset copies |
| `plugins/code-metrics/scripts/fixtures/tool-output/jscpd-aligned3.json` | Create | capture, relative names |
| `plugins/code-metrics/scripts/fixtures/tool-output/jscpd-offset3.json` | Create | capture, relative names |
| `plugins/code-metrics/scripts/dispatch.test.sh` | KEEP | its `summary.files == 7` assertion over `fixtures/sources` is untouched by the new fixture tree |

**Sanity Check:**

- `python3 -m unittest plugins/code-metrics/skills/audit-duplication/scripts/test_cluster_clones.py` exits 0.
- `bash plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.test.sh` exits 0
  with a case asserting `summary.clone_groups == 1` and `len(measures[0].instances) == 3` on the
  aligned capture with no registry, and `summary.clone_groups == 2` on the offset capture.
- `cmp` the three aligned copies pairwise: identical;
  `grep -c '^/' plugins/code-metrics/scripts/fixtures/tool-output/jscpd-aligned3.json` prints `0`.
- `bash plugins/code-metrics/scripts/dispatch.test.sh` exits 0 unchanged.

### Phase 3: Registry cluster lines, drift checker, this repo's five lines [TODO]

Review: code-design

Committed on its own (the registry edit fans CI's test selection out to roughly 225 suites).

1. `registry-filter.py`: a line containing ` -> ` is a cluster line: the text before the arrow is
   the canonical path, the whitespace-separated tokens after it are members (literal paths or
   `pathglob` globs); every other non-comment line is a single token taken whole, spaces included.
   Before matching, normalize every instance path to root-relative by joining the cwd-relative
   value onto the cwd and taking `relpath` against `--root` (the dispatcher rebases paths onto the
   cwd, and an anchored glob rejects a `../` prefix). A cluster line sanctions a group when every
   normalized instance equals the canonical path or matches one member, and the instances'
   `dirname`s are pairwise distinct (the glob matcher anchors the whole path, so "prefix before the
   token" is empty for a glob and the single-token prefix rule cannot be reused). `excluded[].path`
   carries the line text. The first matching line in file order wins, stated in the docstring and
   `reference/config.md`.
2. `scripts/check-cross-plugin-source-drift.sh`: in the registry load loop, `continue` on a line
   containing ` -> `, with a comment naming the cluster-line grammar and its reader.
   `check-cross-plugin-source-drift.test.sh`: a marked line neither registers nor reports
   `REGISTRY STALE`; the existing space-bearing-path case stays green.
3. `scripts/cross-plugin-source-registry.txt`: header line "One path-within-plugin per line"
   gains the cluster-line sentence; five cluster lines, each under its own annotation block naming
   its dedicated check (the production-registry policy test resets its comment block after every
   entry): `lib/hook-utils.sh -> plugins/*/hooks/hook-utils.sh` (`scripts/sync-hook-utils.sh --check`);
   `lib/rewrite-guard.sh -> plugins/*/hooks/rewrite-guard.sh` (`scripts/sync-rewrite-guard.sh --check`);
   `lib/index-regen.sh -> plugins/*/scripts/index-regen.sh` (`scripts/sync-index-regen.sh --check`);
   `lib/resolve-convention-pattern.sh -> plugins/*/hooks/resolve-convention-pattern.sh`
   (`scripts/sync-resolve-convention-pattern.sh --check`);
   `lib/parse-concern-value.sh -> plugins/*/skills/*/scripts/parse-concern-value.sh plugins/*/skills/*/scripts/lib/parse-concern-value.sh`
   (`scripts/sync-parse-concern-value.sh --check`). Before committing, run the Phase 3 probe below
   and add a line only for a surviving root `lib/` group that a sync script declares.
4. Fixture registry `scripts/fixtures/registry/cluster.txt` gains a commented cluster-line example
   and its header sentence; `test_registry_filter.py` gains: a cluster line excludes a
   canonical-plus-copies group; a glob member matches; two instances in one directory keep the
   group; a single-token path containing a space still matches whole; first matching line wins
   when both shapes match; instances given cwd-relative from a subdirectory still match.
5. Prose that restates the grammar: `reference/config.md` `duplication.registries` row,
   `plugins/claude-config/skills/audit-pass/reference/exclusion-set.md` line 18 ("entries are paths
   within each plugin"), and the SKILL.md configuration paragraph (Phase 5).

**Files Affected**

| File | Action | What changes |
|---|---|---|
| `plugins/code-metrics/skills/audit-duplication/scripts/registry-filter.py` | Modify | cluster grammar, root normalization, precedence |
| `plugins/code-metrics/skills/audit-duplication/scripts/test_registry_filter.py` | Modify | six cases |
| `plugins/code-metrics/scripts/fixtures/registry/cluster.txt` | Modify | example line, header |
| `scripts/check-cross-plugin-source-drift.sh` | Modify | skip marked lines |
| `scripts/check-cross-plugin-source-drift.test.sh` | Modify | one case |
| `scripts/cross-plugin-source-registry.txt` | Modify | header, five annotated cluster lines |
| `plugins/code-metrics/reference/config.md` | Modify | registries row text |
| `plugins/claude-config/skills/audit-pass/reference/exclusion-set.md` | Modify | one sentence |

**Sanity Check:**

- `python3 -m unittest plugins/code-metrics/skills/audit-duplication/scripts/test_registry_filter.py` exits 0.
- `bash scripts/check-cross-plugin-source-drift.sh --check` exits 0 on this tree;
  `bash scripts/check-cross-plugin-source-drift.test.sh` exits 0 (including the production-registry
  policy case).
- Runtime probe (SKIP when absent) with jscpd 5.2.0 on PATH, from the repository root:
  `audit-duplication.sh --json --registry scripts/cross-plugin-source-registry.txt --all | jq '[.measures[]|select(any(.instances[]; .file|test("^lib/")))]|length'`
  prints `0`, and `jq '[.excluded[]|select(.path|startswith("lib/hook-utils.sh"))]|length'`
  prints `1` with that entry's `instances` length equal to
  `$(scripts/sync-hook-utils.sh --print-manifest | grep -c copy) + 1`; the same two commands run
  from `plugins/code-metrics` with `--registry ../../scripts/cross-plugin-source-registry.txt`
  print the same values.

### Phase 4: Report sort, rollups, additive summary fields, summary line, no-detector headline [TODO]

Review: code-design

1. `report.py summarize` gains an optional `--root`: when clone-group rows exist, add `by_lane`
   (lane to `{groups, duplicated_lines}`) and `by_directory` (every ancestor directory of each
   group's first instance after root-normalization, cumulative, root as `.`, same shape); emit
   both as empty maps when a duplication collector ran and no group survived. `assemble` and
   `resummarize` accept `--root`; `audit-duplication.sh` passes it to `resummarize`, so the maps
   are computed over surviving groups after exclusion. A group is attributed to its first
   instance's ancestors (instances are path-sorted by Phase 2), so the identity that holds is
   `by_directory["."]["duplicated_lines"] == summary.duplicated_lines` and the per-lane sum; rows
   below the root cannot be summed, which the schema reference states.
2. `report.py assemble`: a `partial` run row counts as measured for document `status`, so an
   all-skipped lane yields `partial`, not `empty`, and the `Unavailable:` line is followed by a
   `Partial:` line naming lanes that skipped files.
3. `report.py render`: for a document with clone-group rows, sort measures by `values.lines`
   descending, then `tokens`, then first instance path (other skills keep today's sort); add a
   `## Rollup` section after Measures with a per-lane table and a per-directory table listing
   directories whose depth is at most `--rollup-depth` (default 2; `audit-duplication.sh` passes
   the resolved key); render the summary line as `Files with clones: N.` when the document is
   duplication-shaped (any `instances[]` row or `skill == "audit-duplication"`), otherwise today's
   line byte for byte; when a duplication document has an empty `excluded[]`, print
   `Excluded by a sanctioned-replication registry: 0 (no registry configured).`; when every
   `duplication` run row is `unavailable`, emit one headline under the title with the first
   non-null `hint` and `/code-metrics:setup`, and print each lane row's reason unchanged.
4. `reference/report-schema.md`: document `by_lane`, `by_directory` (attribution rule, root
   identity, empty-map floor), the run row's `hint`, the `partial` document status for a lane that
   skipped files; add the sentence that readers ignore unknown keys; note "intentional clones"
   beside "sanctioned replication" in the `excluded` row.
5. `test_report.py`: rollup sums and root identity; cumulative ancestors; depth cut in markdown
   only; empty maps on a clone-free duplication run; sort order; summary line per skill (the
   existing exact-dict assertion for a size document stays untouched); no-registry sentence;
   no-detector headline once; `partial` document status; a size document renders byte-identically.

**Files Affected**

| File | Action | What changes |
|---|---|---|
| `plugins/code-metrics/scripts/report.py` | Modify | rollups, `--root`, status, sort, summary line, headline |
| `plugins/code-metrics/scripts/test_report.py` | Modify | nine cases |
| `plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.sh` | Modify | pass `--root` and `--rollup-depth` |
| `plugins/code-metrics/reference/report-schema.md` | Modify | fields, status, ignore-unknown rule, term |

**Sanity Check:**

- `python3 -m unittest plugins/code-metrics/scripts/test_report.py` exits 0.
- `audit-duplication.sh --all | grep -c 'Functions:'` prints `0` and
  `audit-duplication.sh --all | grep -c '^Files with clones:'` prints `1`;
  `audit-size.sh --all | grep -c 'Functions:'` prints `1`.
- `audit-duplication.sh --json --all | jq '([.summary.by_lane[].duplicated_lines]|add) == .summary.duplicated_lines and .summary.by_directory["."].duplicated_lines == .summary.duplicated_lines'`
  prints `true`.
- `PATH=<empty prefix> audit-duplication.sh --all | grep -c 'npm install -g jscpd'` prints `1`.

### Phase 5: SKILL.md, README, CHANGELOG, version, dogfood [TODO]

1. `skills/audit-duplication/SKILL.md`: configuration section names the three new keys, the
   `0`-means-null rule, and both registry line shapes; "Run it" gains the no-detector instruction
   (offer the install command to the user, run it only on confirmation, never silently); "Reading
   the numbers" states clone classes (byte-aligned copies merge, offset copies stay separate), the
   `partial` row and document status, the rollup and its root identity; the pairs gotcha is
   rewritten; `## Next` stays before `## Gotchas`. Prose in house style (`/ai-slop:audit` on the
   file).
2. `README.md`: the audit-duplication row mentions clone classes, rollups, and the cluster line;
   the known-gaps bullet's list of prose-restated defaults is checked against what SKILL.md now
   restates.
3. `CHANGELOG.md`: `## [0.1.9]` with Added / Changed / Fixed entries, one per Brief item, including
   the offset-copies limitation and the `partial` reading; `.claude-plugin/plugin.json` version 0.1.9.
4. Dogfood: `scripts/affected-tests.sh --run` over the whole diff (exit 0, or exit 3 whose `NOT
   RUN` list is Python suites, each then run with `python3 -m pytest`); `scripts/run-ruff.sh check`
   over the changed Python; `shellcheck` and `shfmt -d` over changed shell; both jscpd majors'
   whole-tree runs recorded here as distilled numbers (surviving groups, duplicated lines,
   exclusions, partial lanes) with no memory-slice paths.

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
- `scripts/affected-tests.sh --run` exits 0, or exits 3 with every `NOT RUN` line naming a
  `test_*.py` that then passes under `python3 -m pytest`; `scripts/run-ruff.sh check plugins/code-metrics scripts/check-code-metrics-config-reference.py` exits 0.
- `grep -n '^## Next' plugins/code-metrics/skills/audit-duplication/SKILL.md` precedes `^## Gotchas`;
  `grep -c '5\.1\.2' plugins/code-metrics/reference/collectors.md plugins/code-metrics/scripts/collectors/test_jscpd.py plugins/code-metrics/skills/audit-duplication/scripts/audit-duplication.test.sh` prints `0` for each.
- `markdownlint-cli2` over the changed markdown exits 0.

### Alternatives Considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Detect skips as files-passed minus `statistics.total.sources` | contradicted: `sources` counts token sources that reached detection, reproduced on 4.3.0 and 5.2.0 | jscpd adds a per-file skip list to its JSON report |
| Keep jscpd's per-major defaults, detect only | jscpd 4.x users silently lose every file over 1000 lines | jscpd 4.x line reaches end of life |
| Any whitespace marks a cluster line | the drift checker's tests protect a registered path containing a space | the registry documents a no-spaces rule for paths |
| A tab or a leading sigil as the cluster marker | less readable than `->` in a hand-edited file; equally unambiguous | a consuming repository has a path containing ` -> ` |
| Merge pairs inside the jscpd adapter | a second pair-reporting collector would need it again; the rule is about the report | no other collector ever reports pairs |
| A second registry file for cluster lines | two registries for one concept; the plugin's docs already name this file as the shape | a second reader of the registry file cannot be taught to skip marked lines |
| `by_directory` as direct-parent rows | no documented precedent; a plugin's files would never roll up to the plugin | a consumer needs non-overlapping per-directory sums |
| Stderr prefix as the adapter-to-dispatcher channel | `dispatch.sh` reads stderr only on failure and truncates it; a file is unambiguous and output-testable | the adapter contract grows a structured stderr protocol |
| Strip the install hint out of the run row's reason for the headline | the hint itself contains parentheses and multi-tool lanes concatenate several | never; an additive `hint` field is strictly simpler |
| Exclude `plugins/miro/dist/` through a repo config so no file is skipped here | hides the `partial` reading the change exists to produce; a config is the consuming repo's choice | the repo adopts a `.claude/code-metrics.yaml` for other reasons |

### Test Strategy

Output-based tests drive every script at its command line with fixture inputs and assert on the
printed document, per the TDD principles skill's decision order (output first, state second,
communication last). jscpd is the one unmanaged out-of-process dependency and stays stubbed by a
fake binary that replays a committed capture; nothing in-process is mocked: `cluster-clones.py`,
`registry-filter.py`, and `report.py` are driven for real by `audit-duplication.test.sh` and
`dispatch.test.sh`. One communication-based assertion exists because the boundary is the tool's
argv: `test_jscpd.py`'s existing `argv_log` stub asserts the explicit caps. Red first: each phase
writes its failing test against the named boundary, then the change.

Test boundaries (all existing unless marked): `jscpd.py collect` argv and partial-reason output
(existing CLI, new env vars); `dispatch.sh` run rows (existing, new `hint` field);
`cluster-clones.py` stdin/stdout (new script, same document contract as `registry-filter.py`);
`registry-filter.py --registry --root` (existing); `report.py summarize|resummarize|render`
(existing, new `--root` and `--rollup-depth` arguments); `audit-duplication.sh --json` (existing);
`check-cross-plugin-source-drift.sh --check` (existing). A boundary implementation picks that this
list does not name is a deviation logged to `DEVIATIONS.md` beside this file.

Edge cases named in the Brief's criteria: offset copies; overlapping-but-not-identical ranges; two
copies in one directory; a space-bearing single-token path; a subdirectory cwd; all files skipped;
a `0` cap; no registry configured; a lane whose collector never resolved; a clone-free duplication
run. Existing tests updated: `audit-duplication.test.sh`, `test_jscpd.py`,
`check-cross-plugin-source-drift.test.sh`, `test_registry_filter.py`, `dispatch.test.sh`;
`test_setup_apply.py` passes unchanged once the template carries the keys.

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| jscpd 4.x argv differs from 5.x for a passed cap | Low | Med | both majors verified this session (`--max-lines`, `--max-size` share names; raw byte counts accepted); Phase 1's probe runs both |
| A marked registry line breaks a reader not found in pre-flight | Low | High | pre-flight grepped all 12 mentions; the drift-checker test case is the guard; the registry edit selects every suite referencing it |
| The union-find joins two different fragments | Low | Med | the key requires identical range and equal `lines`; the offset fixture asserts two groups |
| `by_directory` differs by jscpd major | Low | Low | merged instances are path-sorted; the probe compares instance sets, not order |
| The sort or summary change alters other skills' markdown | Low | Med | both branches are gated on clone rows; `test_report.py` asserts a size document renders byte-identically |
| Full-corpus CI run on the registry commit hides an unrelated red | Med | Low | Phase 3 is its own commit; `--check` and its test run locally before the push |
| Version bump without changelog entry fails CI | Low | Low | Phase 5 sanity check runs the parity gate |

## Blast radius

MEDIUM. About thirty files across one plugin and two repo tooling scripts; one CI gate script and
the registry it reads change, which fans `scripts/affected-tests.sh`'s selection out to most of
the corpus; every change is a revertable commit on a feature branch; the config reference gate,
the changelog parity gate, the drift checker's own test, and the plugin's suites cover it.

## Stress-test summary

Both passes ran on the first draft in fresh contexts. The plan reviewer returned 2 CRITICAL, 9
IMPORTANT, 8 SUGGESTION; `/planning:devils-advocate` returned 1 CRITICAL, 7 HIGH, 6 MEDIUM, 3 LOW,
with probes against both jscpd majors. Every load-bearing finding was verified against the tree
before being applied: the eighteen-instance count; the 1.45mb minified file in the typescript
lane; the non-identical `hook-telemetry-sink.sh` pair with no sync script; the drift test's
annotation-block-per-entry policy and its protected space-bearing path; the zero floor keyed on
`ok`; the cwd rebase of instance paths; the hint glued into the reason string; the whole-path
anchoring of the glob matcher; jscpd's star-shaped pairs with the hub on the last input (4.x) or
the first (5.x); offset copies producing ranges that differ by one line; the fixture-count
assertion in `dispatch.test.sh`; and `affected-tests.sh`'s exit-3 contract. No research-iterate
round was needed: every contested claim was settled by a probe the reviewing agent ran and this
session reproduced.

## Execution shape

Fully sequential: 1 → 2 → 3 → 4 → 5. `audit-duplication.sh` is edited in Phases 1, 2, 3 and 4,
`registry-filter.py` in Phases 1 and 3, and Phase 4 renders the shape Phases 2 and 3 produce, so
no two phases are file-disjoint and no parallel wave exists. All-main-session execution.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | adapter, dispatcher, and config edits interlock; the runtime probe needs the session's scratch jscpd prefixes |
| 2 | main-session | small new script plus captures that must be rewritten by hand to relative names |
| 3 | main-session | a CI gate script and the registry change together and are committed alone |
| 4 | main-session | one shared renderer; judgment on byte-identical sibling output |
| 5 | main-session | prose in house style, release bump, dogfood numbers recorded in this file |

## Open questions

None at approval time beyond the gates below.

## Handoff to implementation

### User-approval gates

- The four Brief corrections in the scope-change note at the top of the Brief (instance count,
  the `partial` typescript row, the dropped sixth registry line, the byte-aligned merge caveat)
  and the `->` marker, which amends the grammar the interview locked; approving this plan approves
  them. Any later change to an acceptance criterion stops and asks.

### Execution shape ([EXEC-SHAPE] tagged)

- Sequential phases with Phase 3 as its own commit; per-phase sanity checks as written; the
  partial-reason file channel; the large explicit `--max-lines` and the bound-plus-one byte cap
  passed to jscpd so the adapter's pre-filter is the only gate; fixtures placed outside
  `fixtures/sources`; scratch-prefix jscpd installs for probes with `SKIP` when absent.

### Mechanical work

- One commit per phase (Phase 3 alone), each carrying its `[DONE]` tag flip in this file; run the
  phase's sanity checks before committing; push after each commit. Sequential fallback is not
  needed (no parallel wave). At PR time, run `/planning:plan close-out`.
