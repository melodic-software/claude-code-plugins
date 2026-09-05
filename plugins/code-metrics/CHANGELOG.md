# Changelog

All notable changes to the `code-metrics` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
