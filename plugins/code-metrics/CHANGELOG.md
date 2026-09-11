# Changelog

All notable changes to the `code-metrics` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Added

- **`audit-type-debt` reports per file.** One row per scope file the tool listed (`function`
  null) plus one row per lane labelled `lane-total`; the summary's `Files:` count is the file
  rows, where it read 0 before. The Python lane row sums the file rows, so a change-scoped run
  reports the scope's own coverage rather than everything mypy followed. mypy names modules, not
  files, so the collector re-derives its `--explicit-package-bases` naming from each scope path
  (checked against a real 186-file run of this repository, every listed name matched), matches
  the shorter names a config base such as `mypy_path = src` gives by suffix, and, when nothing
  matches, keeps mypy's own Total as the lane row and says so in the run row's reason. A
  TypeScript file row carries `any_count` alone, the occurrences
  `type-coverage --detail --show-relative-path` lists for the file, because the CLI exposes no
  per-file denominator; the tsconfig program's file set is read through the project's own
  `typescript`, so a scope file the program leaves out gets no row and is counted in the run
  row's reason rather than reported as 0. In the raw rows the lane row comes first, and the
  rendered table leads with it and never drops it under the row cap.
- **mypy's error count reaches the run table.** When mypy exits 1 the Python run row's reason
  reads `mypy reported N errors (M missing stubs)`, the missing ones being the `import-untyped`
  and `import-not-found` codes; `--show-error-codes` and `--no-pretty` are passed so a consumer
  config that hides codes or wraps messages does not hide the count.

### Changed

- **An `ok` run row carries what its collector said on stderr.** The dispatcher dropped an
  adapter's stderr on exit 0; it is now the row's reason (500 characters, newlines folded), and
  null when the adapter said nothing. Every skill's run table gains this.
- **The renderer sorts a `file: null` row among file rows and joins rows per lane.** The
  `lane-total` row and a file row can tie on every earlier sort key, which compared `None` with a
  path; and two lanes' rows with the same values used to join into one line, because the join
  key left the lane out.

### Fixed

- **`audit-type-debt`: an aborted mypy run no longer reads as 100% typed.** mypy exits 2 on a
  blocking error (a duplicate module name, a usage or config error) before analysing anything and
  still writes a report whose only row is `Total 0 0 100.00%`; the collector accepted that as a
  measurement labelled `mypy-reported-errors`, so a repository carrying sanctioned replication read
  as fully typed over zero expressions. Exit 2 is now the adapter contract's exit 4: the Python row
  reads `unavailable` with mypy's own message and the run continues. A Total row with zero
  expressions reports `type_coverage_pct: null`, never 100.
- **`audit-type-debt`: sanctioned replication measures instead of aborting.** The collector passes
  `--explicit-package-bases`, so mypy names each module by its path (`plugins.a.lib.x`) and two
  same-named files under identifier-named directories no longer collide. Same-named files under
  two hyphenated directories still collide, because mypy's module walk stops at a directory whose
  name is not a Python identifier; that case reaches the `unavailable` row above.
- **`audit-type-debt`: no `.mypy_cache/` in the consumer's tree.** The collector passes
  `--cache-dir` with the platform's null device, mypy's documented value for disabling the cache;
  a one-shot report gained nothing from it (6.8s without a cache against 8.2s with a warm one over
  this repository's 179 Python files).

## [0.2.1]

### Changed

- **`audit-size` measures every text file in scope.** Files whose extension no language lane
  claims (markdown, JSON, YAML, PowerShell, a `Makefile`) used to count toward `scope.files` and
  then went unmeasured. They now land in a catch-all `other` lane that the ladder serves with
  `file_lines` alone: `scc` and the bundled counter count any text file, and every other measure
  carries a `not-applicable` row for the lane, so complexity, duplication, type-debt, and
  coverage runs settle exactly as before. `lanes.other.enabled: false` opts the lane out. A file
  the consumer's ecosystem globs leave out of its extension's lane is still dropped, not moved.
- **Lane detection and the run table stop forking per file and per field.** The extension lookup
  returned its lane through a command substitution, one fork per scoped file, and each run row
  was written with one interpreter call per field; the lookup now returns through a variable and
  a row is one call. A whole-tree `audit-size` run on this repository takes about two seconds.
- **A lane's file list reaches its collector through a file, not the argument vector.** The
  dispatcher passes `--paths-from <file>` to every adapter's `collect` verb, read through the new
  shared `scripts/collectors/adapter_paths.py` (positional paths still work and combine with it),
  because a whole repository's lane is thousands of paths and Git Bash under Windows caps a
  native process's command line far below that. The `scc` adapter feeds scc itself in chunks
  under an argument budget (`CODE_METRICS_ARGV_BUDGET` overrides it) for the same reason.
- **A file the scope filter cannot read is named on stderr.** It is still dropped, so one locked
  file does not turn its whole lane unavailable, but it no longer vanishes from the scope with
  nothing said.
- **A file `scc` says nothing about is still counted.** scc lists only the languages it knows,
  so a lockfile or an extensionless text file in the catch-all lane came back with no row and the
  lane still read as measured. The adapter now counts every requested file scc omitted, total and
  blank lines, and labels the row `comment-agnostic` with `lines_comment` and `lines_code` null.
- **The rows under the over-reference block are ordered by the number they report.** After the
  rows over a reference (furthest past it first), the rest sort by the primary reference's value,
  largest first (smallest first for a `below` reference such as coverage), so a size report reads
  longest to shortest instead of alphabetically, and the 200-row cap names the key it kept the
  top rows by. The `thresholds[]` entries now carry `value_key` and `direction` so a consumer of
  the JSON can tell which value a reference was applied to.
- **An empty change says how to widen the scope in the markdown headline too**, beside the run
  row's reason.
- **`Functions:` leaves the summary line when no function rows exist**, which is every
  `audit-size` report in `file-lines` mode.
- **One provenance sentence for the 1000-line reference.** The report, the `audit-size` body, and
  the principles threshold table carry the same words, sourced from `scripts/config-defaults.json`
  and checked by the `audit-size` suite. The `audit-size` description names `--all` as a
  first-class scope alongside the `change` default rather than disowning it.

## [0.2.0]

### Added

- **`scope.registries`**, the sanctioned-replication registry list every audit reads. The
  dispatcher collapses the per-file and per-function rows of every copy of a listed file into one
  row labelled `replicated` with a `replicas` object (`count`, `registry`, `line`, `path`,
  `files`), so a file vendored into ten plugins shows each function once and its over-reference
  count once, and `summary.files` still counts every copy. `duplication.registries` stays as the
  older name, read when the scope-level list is empty. New `scripts/replica-collapse.py` and
  `resolve-config.py --format registries`; `audit-duplication` reads its registries through the
  same format.
- **Default scope exclusions.** `scope.exclude` now defaults to `**/node_modules/**`,
  `**/vendor/**`, `**/dist/**`, and `**/build/**`, and the document carries
  `scope.exclusions[]` (one `{pattern, files}` per glob that matched) so the markdown can say
  which exclusion dropped what. Fixtures and evals stay in scope; a team file that sets the key
  replaces the list whole.
- **The persisted document.** Every markdown run writes the `code-metrics/v1` document it
  rendered to `CODE_METRICS_REPORT_DIR`, else `<CLAUDE_PLUGIN_DATA>/reports`, else
  `~/.claude/plugins/data/code-metrics/reports`, keeping the newest twenty per skill, and the
  table's cap line and the summary name that path. A directory that cannot be written is
  reported on stderr and the cap line says to re-run with `--json` instead. New
  `scripts/persist-report.sh`, sourced by all five entry points, and `report.py render
  --document`.
- **Progress on stderr** for a run whose scope passes two hundred files, or under
  `CODE_METRICS_PROGRESS=1`; `=0` silences it.

### Changed

- **The markdown table joins each function's rows.** One line per function carries every
  collector's values (a cyclomatic row and a Halstead row no longer print the same function twice
  with complementary nulls); a row with no start line joins the one function of its name in the
  file and stays separate when the name is ambiguous, and rows whose values disagree are never
  merged. The JSON keeps one row per collector. A Labels column now shows `start-line-only`,
  `file-level`, `multimetric-approximation`, and `replicated`. Rows over a reference sort by how
  far past it they sit, worst first, then by file. A Halstead value of 0 gets a footnote saying
  it is a measurement.
- **Collectors run in parallel**, one process per lane and measure, capped at the CPU count or
  `CODE_METRICS_JOBS`; the run table and the rows come out in lane order whatever the concurrency.
  The scope's normalization, deduplication, and binary sniff moved from a shell loop with two
  subprocesses per file into `scripts/scope-filter.py`, and `detect-lanes.sh` lower-cases
  extensions in the shell. A whole-tree run on this repository went from 95 seconds to 49, the
  remainder being shellmetrics' own time.
- **An empty change scope says why.** The `*/*` run row's reason names the merge-base ref and
  the `--all` alternative when the branch sits at it with a clean tree, or says the changed files
  belong to no lane.
- **ESLint with no configuration is `unavailable`, not a failed run.** The adapter contract
  gains exit 4, "resolved but cannot run here": `eslint-complexity` returns it when ESLint
  reports that it found no configuration for the files, and the dispatcher writes an
  `unavailable` row carrying ESLint's own message instead of failing the run with exit 3. The
  adapter does not look for a configuration file itself; ESLint resolves it per target file.
- **Version probes for tools with no version flag.** `multimetric` reports the distribution
  version from the interpreter its launcher names, `gocognit` the module version from `go
  version -m`, and both read `version unavailable (<tool> has no version flag)` rather than
  `unknown-version` when nothing answers.

## [0.1.9]

### Fixed

- **The tool-free PATH in the audit suites is derived from the collector ladder.** Each suite
  that builds an environment with collectors removed used to keep a second, hardcoded list of
  tool names off PATH. A collector added to `scripts/collector-ladder.tsv` stayed reachable
  and the no-collector case stopped being tool-free. The excluded set is now the ladder's tool
  column (skipping the reserved `none`, `n/a`, and `deferred` rungs) plus the PATH binaries those
  adapters look up, and after that environment is built the suite asserts that none of those
  collectors still resolves. Python interpreters on that PATH are resolved to a non-mutating
  executable so a pyenv (or similar) shim cannot prepend skipped collectors back onto PATH.

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
