# Changelog

All notable changes to the `code-metrics` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.9]

### Added

- **`audit-duplication` merges detector pairs into clone classes.** `jscpd` and PMD CPD report a
  clone as a pair, so N copies of one fragment arrived as N-1 rows and the summary counted the
  fragment's lines N-1 times. A post-pass (`cluster-clones.py`) now joins rows that share an
  instance with an identical file and line range into one row per class, the instances sorted by
  path and the row labelled `clustered`; the lines count once. The merge joins on identity, not
  overlap: a copy that shares only part of a fragment stays its own group.
- **Explicit size and line caps, reported instead of hidden.** `duplication.max_size` (default
  `1mb`, binary units) and `duplication.max_lines` (default `null`) are applied by the jscpd
  adapter before the tool runs, because jscpd 4 and 5 disagree on their own `--max-size` and
  `--max-lines` defaults and on what `0` means, and neither names a skipped file. A skipped file
  makes the lane's run row `partial` with the count and the largest file, the document `partial`,
  and the markdown summary carries a `Partial:` line. `0` or `null` means no cap.
- **Registry cluster lines.** A sanctioned-replication registry line `<canonical> -> <member>...`
  names a root-relative canonical copy and the plugin paths or gitignore-style globs that carry
  it, so a canonical file outside any plugin (this repository's `lib/hook-utils.sh`) can declare
  its copies; instance paths are compared root-relative and the first matching line wins. A plain
  line is still one path-within-plugin taken whole.
- **Per-lane and per-directory rollups.** `summary.by_lane` and `summary.by_directory` (every
  ancestor of each class's first instance, cumulative) are additive `code-metrics/v1` fields,
  computed after registry exclusion; `duplication.rollup_depth` (default 2) decides how deep the
  markdown `## Rollup` section lists. The schema reference states that readers ignore unknown keys.
- **Run rows carry the install hint as a field.** `run[].hint` holds the first install hint a
  failed probe produced, apart from the prose reason, so a renderer can print it once.

### Changed

- **The duplication markdown reads as a duplication report.** Clone rows are listed largest
  first; the summary line is `Files with clones: N.` instead of the size-shaped `Files. Functions.
  Over reference.`; an empty exclusion list is stated with its reason; and a run in which no clone
  detector resolved for any lane opens with one headline carrying the install hint and
  `/code-metrics:setup`. The skill offers that install to the user and never performs it
  unprompted. Every other skill's document renders as before.
- **`reference/collectors.md` pins jscpd 5.2.0** and records the 4.x maintenance line (4.3.0),
  which the adapter also translates, the binary size grammar, and the token-count difference
  between the majors.

### Fixed

- **A lane that skipped every file is `partial`, not `empty`**, and the zero floor counts a
  `partial` duplication row as measured, so an all-excluded or clone-free lane that skipped a file
  still states `duplicated_lines: 0`.
- **A run from a subdirectory matches the same registry lines as a run from the root**, because
  instance paths are normalized against the repository root before matching.

## [0.1.8]

### Added

- **`audit-complexity`, `audit-coverage`, `audit-duplication`, `audit-size`, `audit-type-debt`,
  `setup`**: a `## Next` section naming the skill that normally runs after this one, in the
  mention-only shape the skill-body rule describes.

## [0.1.7]

### Changed

- **The configuration reference's key table can no longer disagree with the bundled defaults.**
  `reference/config.md` restated every key from `scripts/config-defaults.json` as hand-maintained
  prose, and nothing checked the two against each other, so a key added, removed, or given a
  different default left a stale reference that reads exactly like a current one. A repository gate
  (`scripts/check-code-metrics-config-reference.py`, run on every change) now pins the table's key
  column and default column to that file: every non-reserved defaults leaf must be documented by
  exactly one row, every row must document a key that exists (or be marked `absent`), and each
  row's default must equal the canonical rendering of the value, pipes escaped and backtick fences
  widened so a value carrying markdown-significant characters cannot produce a broken table that
  still passes. The third column stays hand written; the document's prose is unchanged apart from
  a paragraph saying what the gate covers. The prose copies of default values in the skill bodies
  remain unbound and are now recorded in the README's known gaps.

## [0.1.6]

### Fixed

- **A Cobertura class is no longer keyed under the wrong source root.** A multi-root build declares
  several `<source>` roots and each class filename is relative to one of them, but the parser
  collected all the roots and then applied the first one to every filename. A class belonging to a
  later root was keyed under a path that does not exist, so its coverage never joined against the
  measured file and the file read as uncovered or dropped out of the join. A relative filename now
  takes the first declared root under which that path exists in the scanned tree, which the calling
  skill passes as `CODE_METRICS_SCAN_ROOT` rather than leaving the parser to probe whatever
  directory the session happens to sit in. With no candidate on disk the first root still applies,
  a report declaring one root is resolved without reading the filesystem at all and is unchanged,
  and absolute and drive-qualified filenames keep taking no prefix. The on-disk probe can only tell
  the roots apart when they are relative, or absolute and present on the machine running the audit;
  a report whose absolute roots name the machine that produced it (a CI build) misses every
  candidate and still takes the first root, because rewriting a root from another machine onto the
  local tree needs a mapping the report does not carry.

### Added

- A source root skipped for a reason other than the file being absent, an unreadable directory
  above all, now prints one line to stderr per distinct reason instead of being silently
  indistinguishable from a miss. stdout stays the parsed document alone.

## [0.1.5]

### Fixed

- **A short name in the artifact no longer binds to the wrong function.** Where a coverage
  artifact records a function as `run` rather than as `Alpha.run`, the join fell back to matching
  on the trailing component of the name, and a lone record ending in `run` bound to whichever
  function was measured first. Two `run` methods in one file therefore reported the same coverage,
  one of them out of the other method's region, with nothing in the report to say so: a method
  that never ran read as fully covered, and its CRAP followed. The fallback now places each record
  by the lines the artifact recorded for it and binds it to the function whose declared range
  holds them. An exact name still wins outright and is unchanged, and so is a single record whose
  trailing name no other function in the file shares, since a name nothing contests is not a tie
  to break and an artifact built from compiled output numbers its lines differently from the
  source.
- **An unresolvable short name is now refused rather than guessed.** Where the range cannot
  separate the candidates, because the artifact placed none of them at a line (an lcov `FNDA`
  with no `FN` declaration) or because two of them fall inside the same range, the function is
  left unjoined: the row reads `cov_source: ambiguous` with coverage, line counts, hit, and CRAP
  null, cyclomatic kept from the complexity row, and a `coverage-ambiguous` label, and the lane's
  `coverage` run row turns `partial` and names the functions it could not place, so the document
  cannot settle as `complete` over it. A missing number an operator can see beats a wrong number
  they cannot.

## [0.1.4]

### Changed

- **Three descriptions recovered headroom against the Agent Skills field maximum (#3845).**
  `audit-complexity` (1016), `audit-coverage` (1007) and `principles` (1004) all sat within twenty
  codepoints of the spec's 1024-codepoint `description` maximum. A description is the surface an
  author edits to add a trigger phrase, so each of the three was one ordinary edit away from a
  breach the Skills API rejects at upload. They now measure 963, 968 and 949: 53, 39 and 55
  codepoints recovered. The rewrite cut redundancy, not vocabulary. Every single-quoted trigger
  phrase survives verbatim (7, 7 and 6 phrases), confirmed by check 3 of
  `plugins/skill-quality/scripts/check-skill.sh` against `origin/main` rather than by reading the
  diff, because clipping a description is the failure mode that makes a skill undiscoverable.
  No skill's behavior changed.

## [0.1.1]

### Fixed

- **An out-of-scope package no longer credits a scoped file with its coverage.** A basename is the
  weakest evidence `audit-coverage` accepts when it maps an artifact path onto a scoped file, and
  it was checked for ambiguity only among the scoped files. Two services each shipping a
  `handler.go`, with one of them out of scope, mapped both paths onto the scoped file, and the
  out-of-scope package's covered block was unioned into it: a file that never ran reported 50
  percent. A basename must now also be claimed by exactly one artifact path, counted across every
  artifact of that format, because the skill discovers one artifact per coverage file and two
  services' profiles arrive as two documents. The count is per format, since two formats naming one
  basename are one file measured twice: a Go profile writes the module path the compiler saw while
  an lcov tracefile writes the repository path.
- **A line artifact that measured a file and found nothing no longer reports `null`.** Whether any
  line-measuring artifact had covered a file was inferred from whether the merged line table came
  out non-empty, which cannot tell "measured, found no executable line" from "never measured lines
  at all". The first is a `0` and the second a `null`, so a Go file that an lcov section also
  covered reported `null` where the artifact had a real answer. The fact is now recorded as the
  section is merged.

## [0.1.0]

### Added

- **`audit-size`:** lines per file for a change, a path, or the whole tree, comment-aware through
  `scc` when it resolves and comment-agnostic from a bundled counter otherwise, reported beside a
  cited reference (1000 non-blank lines, the plugin's own number) and never as a finding.
- **The dispatcher and report contract:** scope resolution (change, paths, `--all`), lane detection
  by extension with consumer glob overrides, a collector ladder shipped as data
  (`scripts/collector-ladder.tsv`), and the `code-metrics/v1` JSON document with its
  "Coverage of this run" table, `status` of `complete`, `partial`, or `empty`, and the exit-code
  taxonomy 0/2/3.
- **The configuration cascade:** `.claude/code-metrics.yaml` layered as user-global, team, and
  local overlay with per-key override over bundled defaults, read by a bundled parser for a
  documented YAML subset; the consumer's `.claude/ecosystems/<lane>.yaml` `globs` and `enabled`
  honoured for lane detection; `scope.exclude`, per-lane collector overrides validated against
  the ladder, and every reference reported with the layer that supplied it
  (`reference/config.md`).
- **`setup`:** `check` probes the interpreter, each layer (YAML subset, tracked-file guard), the
  resolved references, and every collector adapter; `apply` writes the team layer per key,
  idempotently, without installing anything or touching `.gitignore`.
- **`audit-size` `size.mode: iso-8.2.115`:** the ISO/IEC 5055 §8.2.115 function-percentage form
  as a `function_lines` measure from collectors that report function ranges.
- **`audit-complexity`:** per-function cyclomatic and cognitive complexity and Halstead difficulty
  for TypeScript/JavaScript, Python, Bash, and Go through eight collector adapters (`lizard`,
  `radon`, ESLint's `complexity` rule, `eslint-plugin-sonarjs`, `gocyclo`, `gocognit`,
  `shellmetrics`, `multimetric`), each row carrying its start and end line or a label naming why
  it has none; cyclomatic 20 cites ISO/IEC 5055:2021 §8.2.117 with 10 and 15 selectable.
- **`audit-coverage`:** line coverage per file and per function read from lcov 1.x and 2.2
  (`FNL`/`FNA`), Cobertura, coverage.py JSON (with its 7.6.0 `functions` regions), and Go cover
  profiles, joined to the complexity rows for CRAP per function; artifacts are discovered or
  named, never produced, and a function with no executable lines reports `null`.
- **`audit-duplication`:** clone groups from `jscpd`, `dupl`, or PMD CPD with every instance's
  range, minus the replication a sanctioned-replication registry declares (an exclusion recorded
  in the report, not a suppression).
- **`audit-type-debt`:** the typed-code percentage from `type-coverage` (TypeScript) and mypy's
  `--any-exprs-report` (Python), with a `null` reference because no standard anchors the measure;
  C# reported as not applicable.
- **`principles`:** the metric-literacy router with source-attributed reference files (measures,
  thresholds, CRAP's corrected provenance and the Lewis 2013 mechanism, literature), the
  cross-metric caveats carried once, and gated pointers to the owners of mutation score,
  tautological tests, dead code, coupling, and lint.
- **The dispatcher:** a failed collector probe's stderr is relayed into the run row's reason; a
  `not-applicable` row never withholds `status: complete`; `reference/collectors.md` carries one
  stamped row per collector and artifact format.
- **Change scope from a subdirectory:** the diffed and untracked files are named from the
  repository root and rebased onto the working directory, so a run from a subdirectory keeps the
  whole change (it used to drop every file and report `empty`).
- **Bash floor:** bash 4 or later is required and every entry point says so under an older bash;
  `setup apply` resolves the repository root itself when `--dir` is omitted;
  `CODE_METRICS_HOME` is documented; the setup template is bound to the bundled defaults by a
  test; the coverage join's known limits are in the skill's Gotchas.
- **Reference typing:** a quoted number in a configuration layer (`reference: "20"`) is refused
  by the resolver by key and layer (exit 2; a FAIL `config` row in `setup check`) instead of
  reaching the assembler as a string, and the assembler treats a non-numeric reference as no
  threshold rather than raising.
- **`audit-complexity`:** per-function cyclomatic and cognitive complexity and Halstead
  difficulty through eight adapters (`lizard`, `radon`, ESLint's `complexity` rule,
  `eslint-plugin-sonarjs`, `gocyclo`, `gocognit`, `shellmetrics`, `multimetric`), each row
  carrying its start and end lines or a label naming why it has none; cyclomatic 20 cites
  ISO/IEC 5055:2021 §8.2.117 with 10 and 15 selectable.
- **`audit-duplication`:** clone groups from `jscpd` (every lane), `dupl` (Go), or PMD CPD, with
  a sanctioned-replication registry (design T8) that moves declared clusters into `excluded[]`
  as an exclusion rather than a suppression; the suite carries this repository's
  `hook-utils.sh` cluster as the acceptance case.
- **`audit-type-debt`:** the typed-code percentage per lane from `type-coverage` (TypeScript;
  the probe requires a resolvable `typescript`) and mypy's `--any-exprs-report` (Python); no
  standard or CWE anchors the measure, and C# is reported as not applicable.
- **`principles`:** the metric-literacy router with source-attributed reference files
  (measures, thresholds, CRAP, literature), the cross-metric caveats carried once, and gated
  pointers to the owners of mutation score, tautological tests, dead code, coupling, and lint.
- **Report contract:** a `not-applicable` run row never withholds `status: complete`; a failed
  probe's stderr is relayed into the `unavailable` reason; clone-group rows add
  `summary.duplicated_lines` and `summary.clone_groups`, recomputed through `report.py
  resummarize` after exclusions.
