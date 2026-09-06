---
description: "Read coverage artifacts a build already produced (lcov `.info` including the 2.2 `FNL`/`FNA` records, Cobertura XML, coverage.py JSON, a Go cover profile) and report line coverage per file and per function for a change, a path, or the tree, plus CRAP per function (`comp^2 * (1 - cov/100)^3 + comp`, Savoia and Evans 2007) from the sibling complexity numbers. It never runs a test command and installs nothing. A missing artifact is a warning naming the paths searched, never a silent skip; a function with no executable lines reports null, not 0. Coverage and CRAP both default to a null reference (no bar) printed with its provenance; no finding, severity, or exit-code gate is emitted. Use when: 'coverage of this change', 'coverage per function', 'CRAP score', 'which functions are complex and untested', 'read the lcov report', 'coverage.xml', 'how covered is this file'; for complexity alone use /code-metrics:audit-complexity; for what these numbers can and cannot tell you, /code-metrics:principles."
argument-hint: "[--json] [--all] [--base <ref>] [--artifacts <path>]... [<path>...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/audit-coverage.sh:*)", "Bash(git branch --show-current:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Coverage and CRAP read from build artifacts, no verdict
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Coverage is a dynamic measure. This skill reads it statically: it parses an artifact a test run
already wrote and joins it to the functions in scope. Running the tests is the project's own job
and stays there, so nothing here executes a test command, starts a runner, or installs a tool.

Two numbers come out. Line coverage per file and per function is read from the artifact. CRAP per
function is derived: `comp^2 * (1 - cov/100)^3 + comp`, where `comp` is the function's cyclomatic
complexity from the sibling `audit-complexity` script, run over the same scope.

| Format | Written by | What the join gets from it |
|---|---|---|
| lcov `.info` | most JavaScript and C/C++ toolchains, `coverage lcov` | line hits; function records from `FN`/`FNDA` (1.x) or `FNL`/`FNA` (2.2 and later), which is where a function end line can come from at all |
| Cobertura XML | gcovr, coverlet, kcov (which is how a Bash lane gets an artifact) | line hits, `<sources>` prefixes, and `<method>` regions with their hit flag |
| coverage.py JSON | `coverage json` | executed and missing lines, and the per-function regions it has carried since 7.6.0 |
| Go cover profile | `go test -coverprofile` | statement counts over line ranges, which is not a line table: the profile never says which lines carry the statements, so a Go file reports the statement ratio `go tool cover -func` prints, labels it `cov_source: statement-ratio`, and reports `lines_executable` and `lines_hit` as null. The format names no functions either, so a Go function reports `coverage_pct` and `crap` as null, and its line counts as null unless a line-measuring artifact also covered the file |

The SQLite data file coverage.py writes while measuring is never read: its schema is internal by
its own documentation and free to change without a major version bump. Run `coverage json` or
`coverage lcov` and point this skill at the result.

## Run it

```bash
"${CLAUDE_SKILL_DIR}/scripts/audit-coverage.sh"                                  # the change, with the artifact auto-discovered
"${CLAUDE_SKILL_DIR}/scripts/audit-coverage.sh" --artifacts build/lcov.info src/ # an explicit artifact and an explicit scope
"${CLAUDE_SKILL_DIR}/scripts/audit-coverage.sh" --all --artifacts coverage.xml --artifacts cover.out
"${CLAUDE_SKILL_DIR}/scripts/audit-coverage.sh" --json --all                     # the code-metrics/v1 document instead of markdown
```

With no `--artifacts` and no `coverage.artifacts` in the config, the well-known names are looked
for under the repository root, at most two directory levels deep and never inside `node_modules`,
`.git` or `vendor`: `coverage/lcov.info`, `lcov.info`, `coverage.xml`, `cobertura.xml`,
`coverage.json`, `coverage.out`, `cover.out`. Each artifact's format is detected from its content,
not its extension.

Present the markdown report as printed: the scope, the "Coverage of this run" table, the
references with their provenance, then one row per file and per function. Keep the `--json`
document when the numbers feed a comparison: pass it to `/verification:measure metrics` when the
`verification` plugin is installed, treating `status: empty` on either side as INCONCLUSIVE;
otherwise keep the JSON beside your notes and compare by hand.

## Reading the numbers

- A file row is the artifact's own line table: `coverage_pct`, `lines_executable`, `lines_hit`.
  A file a Go cover profile covers is the exception: the profile weighs statements, so the
  percentage is its statement ratio, `cov_source` reads `statement-ratio`, and both line counts
  are null.
- A function row exists for every function whose complexity collector reported a real end line.
  It carries `coverage_pct`, `cyclomatic`, `crap`, and, in the JSON, `cov_source` and `hit`.
- `cov_source` says where the coverage came from: `artifact-region` when the artifact carried the
  function's own region (coverage.py `functions`, a Cobertura `<method>`, an lcov 2.2 `FNL` end
  line), `line-range` when the range came from the complexity collector, in which case nested
  function ranges are subtracted from the parent first, and `statement-ratio` on a file row whose
  percentage came from a Go profile's statements rather than from a line table. The markdown table
  renders the values; the per-row `cov_source` and `hit` fields are in the `--json` document.
- `hit` is the artifact's function-hit flag. When it says the function was never entered,
  `coverage_pct` is 0 rather than the 1/N a declaration line executed at import would produce.
- A function with no executable lines in the artifact reports `coverage_pct: null` and
  `crap: null`, never 0: a fabricated 0 percent would produce a fabricated maximal CRAP. Its
  `lines_executable` and `lines_hit` are 0 when an artifact that measures lines covers the file
  and carries none in that range, and null when no artifact covering the file measures lines at
  all, which is every function of a file only a Go profile covers.
- CRAP is Savoia and Evans' formula (Agitar Labs, 2007). It is a description of two numbers you
  already have, not a validated predictor of change risk, and no standard sets a threshold for it.
  `/code-metrics:principles` carries the provenance, the rename history, and the caveats; read it
  before you quote a CRAP number at anyone.
- A lane whose resolved complexity collector reports no function end lines gets a `<lane>/crap`
  row with `status: not-applicable` and that reason. Bash is that lane in this version: no
  maintained Bash collector reports an end line, so Bash CRAP is a stated gap, not a null.
- A lane matched by fewer than all of its scope files carries `status: partial` and the reason
  `partial, N of M scope files present in the artifacts`, so a total miss never reads as "no
  executable lines" and the document cannot settle as `complete` while a row says `N of M`. A lane
  no artifact covers is `unavailable` with that count; when no artifact was found at all, the
  reason lists every path searched.
- Whether the covered code is actually checked by its tests is a different question, and coverage
  alone cannot answer it: a line can execute under a test that asserts nothing.
  `/mutation-testing:audit` owns that question when the `mutation-testing` plugin is installed;
  without it, say that the coverage number is an execution count and stop there.
- Exit 0 whenever a report was produced, including an empty one; exit 2 for a usage error, which
  includes a named artifact or scope path that does not exist; exit 3 when a complexity collector
  ran and produced nothing parseable, with its stderr in the run table.

## Configuration

Everything tunable resolves through `.claude/code-metrics.yaml` (user-global, team, local
overlay; per-key override; keys in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`):

| Key | Default | Effect |
|---|---|---|
| `coverage.artifacts` | `[]` | Explicit artifact paths; empty means auto-discover. A listed path that does not exist is a usage error, so a stale entry is loud |
| `coverage.path_prefix_strip` | `[]` | Prefixes removed from artifact paths before the join, for compiled-output layouts (`dist/`, `build/`) |
| `coverage.reference` | `null` | No bar. A number counts rows below it as `over_reference` and nothing else |
| `coverage.crap.reference` | `null` | No bar; no standard sets one for CRAP |

`/code-metrics:setup` writes the team file and probes the collectors.

## What this skill does not do

- It never runs tests, starts a test runner, or installs a coverage tool. It reads what a build
  already wrote; if there is no artifact, the report says so and stops.
- It never reads the SQLite data file coverage.py writes while measuring.
- It never judges. A reference here is a value to count against, and no finding, severity, or
  exit-code gate follows from one.
- It does not measure branch, condition, or MC/DC coverage. Those records are parsed past, not
  reported, because the join is a line-level one.

## Gotchas

- The complexity collector decides which functions can carry CRAP at all. With no collector
  resolving for a lane, that lane has no function rows and its `<lane>/crap` row is `unavailable`
  naming the collector's own reason. File-level coverage is unaffected: the scope the join keys on
  is the one the audits measure, not the files a complexity collector emitted rows for, so a file
  with no functions still reports its lines.
- Path shapes differ between artifact and source tree. The join normalizes both sides, strips the
  repository root and the configured prefixes, then falls back to a component-wise suffix match
  and finally to a unique basename (which is how a Go profile's module path resolves). Both
  fallbacks require a single winner: an artifact path that fits two scoped files equally well
  (two services vendoring the same `pkg/a.py`) stays unmatched and shows up in the partial count,
  because attributing it to either would credit one service with the other's coverage. The
  basename fallback needs a single winner on the artifact side too, counted across every artifact
  read rather than within one: when two services each ship a `handler.go` and only one is in
  scope, the out-of-scope path stays unmatched instead of merging its coverage into the scoped
  file, even though the scope names exactly one candidate.
- An artifact older than the source it describes joins by line number and will be wrong without
  saying so. Re-run the tests before reading the numbers when the diff has moved lines.
- Two artifacts covering one file are merged by keeping the larger hit count per line, so a line
  is never counted twice. Two artifacts covering one function are folded the same way: the hit
  flag is the larger of the two, so a suite that never entered the function cannot report it at 0
  percent beside a file row the other suite already showed as covered. Two Go profiles covering
  one file merge block by block on the profile's own `start.col,end.col` identity and are totalled
  after that, so two test shards that entered different blocks report what they covered between
  them rather than what the luckier shard covered alone.
- A Go profile and a line artifact naming the same `.go` file do not average or overwrite each
  other: the profile's statement ratio is that file's exact native measure and wins the
  percentage, the row says `statement-ratio`, and the line counts stay null rather than reading as
  the counts behind a number they did not produce. The lane's `collector` still names both formats
  read. Function rows are line-based, so a Go function does take its region from a line artifact
  when one covers it.
- A Cobertura report with several `<source>` roots is read against all of them: a relative class
  filename takes the first root under which that path exists in the scanned tree, and falls back
  to the first root when no candidate exists. Two roots that both hold the file is an ambiguity
  the report cannot settle, so the first one wins and the class lands under it. The probe settles
  anything only when the roots are relative, or absolute and present on the machine running the
  audit. A report built elsewhere declares absolute roots (the usual coverlet, kcov and gcovr shape
  for a CI run) naming directories this machine does not have, so every candidate misses and every
  class lands under the first root the way it did before the roots were read at all. Rewriting a
  root from another machine onto the local tree needs a mapping the report does not carry.
- Two functions in one file whose qualified names share a tail (`A.run` and `B.run`) can bind to
  each other's artifact region when the artifact carries only the short name; the file-level
  numbers are unaffected.
