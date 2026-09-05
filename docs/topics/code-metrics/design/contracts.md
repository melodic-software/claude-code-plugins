# code-metrics contracts

The three contracts the plugin exposes: the consumer config surface, the JSON report every audit
script emits, and the collector adapter interface a new lane or tool implements. Resolved threads
that shape them are in [`design-threads.md`](design-threads.md).

## 1. Config surface: `.claude/code-metrics.yaml`

Layered per `docs/conventions/config-cascade/` (user-global `~/.claude/code-metrics.yaml`, team
`.claude/code-metrics.yaml`, overlay `.claude/code-metrics.local.yaml`). **Merge form: per-key
override**, declared here because every value is a scalar or a closed list. Unknown keys are inert.
All three layers absent is valid: every key below has a bundled default.

```yaml
# .claude/code-metrics.yaml  (contract: code-metrics config v1)
scope:
  default: change          # change | all
  base: auto               # auto (merge-base with the default branch) | <ref>
  exclude: []              # extra path globs dropped from every measure

complexity:
  cyclomatic:
    reference: 20          # provenance: ISO/IEC 5055:2021 §8.2.117 (normative)
    # selectable alternatives the report can cite when set:
    #   10  McCabe 1976, "reasonable, but not magical"
    #   15  NIST SP 500-235, with its six practices
  cognitive:
    reference: null        # Campbell, SonarSource; no standard sets a threshold
  halstead:
    difficulty: null       # Halstead 1977; no standard sets a threshold

size:
  mode: file-lines         # file-lines | iso-8.2.115
  file_lines: 1000         # plugin default; not ISO-backed (informative figure only)
  function_lines_pct: 5    # ISO/IEC 5055:2021 §8.2.115, used when mode is iso-8.2.115

duplication:
  min_tokens: 50           # passed to the collector (jscpd --min-tokens)
  min_lines: 5             # passed to the collector (jscpd --min-lines)
  ignore: []               # collector ignore globs (jscpd --ignore)
  registries: []           # sanctioned-replication registries, one relative path per line

coverage:
  artifacts: []            # explicit artifact paths; empty means auto-discover
  path_prefix_strip: []    # prefixes removed from artifact paths before the join (compiled-output layouts)
  reference: null          # no default bar; the plugin never argues for 100%
  crap:
    reference: null        # Savoia and Evans 2007; not a validated predictor

type_debt:
  reference: null          # no standard or CWE anchors the measure

lanes:
  typescript:
    enabled: true
    collectors:            # measure -> ordered tool list; absent means the bundled order
      cyclomatic: [lizard, eslint-complexity]
  python:
    enabled: true
  bash:
    enabled: true
  go:
    enabled: true
  dotnet:
    enabled: true          # detected, reported as deferred in V1
```

The file is written in the YAML subset the plugin reads (design thread T22): block mappings, block
sequences, flow sequences of scalars, scalars, comments. No flow mappings, anchors, or multi-line
scalars.

Rules:

- A `reference` of `null` means "report the value, count nothing as over". A number means "count
  values at or above it as `over_reference`". Neither produces a finding, a severity, or an exit
  code (design thread T6).
- `lanes.<lane>.collectors.<measure>` replaces the bundled ordered list for that measure in that
  lane (per-key override applies at this leaf, so one measure can be overridden without touching
  the others).
- `lanes.<lane>.enabled: false` opts the lane out even under `--all`. When the consumer tracks
  `.claude/ecosystems/<lane>.yaml`, that file's `globs` and `enabled` are read first; this key is
  the plugin-specific override on top.
- The report prints every resolved key it used and which layer supplied it when a personal layer
  changed a value (provenance reporting).

## 2. Report JSON: `code-metrics/v1`

Every audit script prints exactly one JSON document to stdout. Diagnostics go to stderr. The skill
renders markdown from this document and never from stderr.

```json
{
  "schema": "code-metrics/v1",
  "skill": "audit-complexity",
  "generated_at": "2026-09-05T12:00:00Z",
  "status": "partial",
  "scope": { "mode": "change", "base": "a1b2c3d", "files": 12, "excluded": 1 },
  "run": [
    { "lane": "typescript", "measure": "cyclomatic", "collector": "lizard 1.24.0", "status": "ok", "reason": null },
    { "lane": "python", "measure": "cognitive", "collector": null, "status": "unavailable", "reason": "no maintained collector found (validated 2026-09-04)" },
    { "lane": "dotnet", "measure": "cyclomatic", "collector": null, "status": "deferred", "reason": "C# lane deferred; research tag probe:dotnet-metrics-linux" }
  ],
  "thresholds": [
    { "measure": "cyclomatic", "reference": 20, "provenance": "ISO/IEC 5055:2021 §8.2.117 (normative)", "layer": "bundled default" }
  ],
  "measures": [
    { "file": "src/a.ts", "function": "parse", "start_line": 10, "end_line": 42, "lane": "typescript",
      "values": { "cyclomatic": 23, "cognitive": null }, "over_reference": ["cyclomatic"] }
  ],
  "summary": { "files": 12, "functions": 88, "over_reference": { "cyclomatic": 3 } },
  "excluded": [],
  "unavailable": [ "python/cognitive", "bash/cognitive" ]
}
```

Field rules:

- `run[]` is the "Coverage of this run" table. `status` is one of `ok`, `unavailable`,
  `not-applicable`, `deferred`. A non-`ok` row always carries a non-null `reason`.
- `measures[]` rows are per function for cyclomatic, cognitive, Python Halstead, and CRAP
  (`lizard` and `radon` both emit start and end lines, probed 2026-09-05); per file for size and
  for `multimetric` Halstead (`function: null`); per clone group for duplication (`instances[]`
  replaces `file`/`function`); per lane for type debt (`values.type_coverage_pct`,
  `values.any_expressions`).
- `values.<measure>` is a number or `null`; `null` means "not measured for this row", never zero.
- `excluded[]` (duplication only) lists clone groups dropped by a registry, each with the registry
  path and line that sanctioned it.
- `status` is `complete` (every implied lane and measure ran; a `not-applicable` row implies
  nothing and never withholds it), `partial` (at least one `unavailable` or `deferred` row),
  or `empty` (nothing was measured; the markdown headline reads "Measured nothing"). A consumer
  comparing two reports treats `empty` on either side as INCONCLUSIVE.
- `scope.files` of `0` (a docs-only change) yields `status: empty` with one `run[]` row
  `*/*: not-applicable, reason: no measurable files in scope`.
- Coverage rows carry `cov_source` (`artifact-region` or `line-range`) and `hit` (the artifact's
  function-hit flag, or `null`); a lane whose collector reports no function end lines carries a
  `<lane>/crap: not-applicable` run row (design T7).
- Exit code: `0` when the document was produced, including `empty` runs; `2` for a usage error,
  which includes an explicitly named path (`--artifacts`, `--registry`, a scope path) that does not
  exist; `3` when a resolved collector ran and produced no parseable output (its stderr is
  relayed). A collector's own non-zero exit is not a failure when it produced output.

## 3. Collector adapter contract

An adapter is one Python file, `plugins/code-metrics/scripts/collectors/<tool>.py` (invoked through the resolved interpreter; a bash adapter would shell out to a Python translator anyway, so the translator is the adapter), that implements these verbs on its command line:

| Function | Contract |
|---|---|
| `probe` | Prints the tool's version to stdout and exits 0 when the tool resolves; exits 1 otherwise. Never installs. |
| `measures` | Prints the `lane/measure` pairs the adapter can produce, one per line. |
| `collect <lane> <measure> <file>...` | Runs the tool on the files and prints `code-metrics/v1` `measures[]` rows (JSON lines) to stdout. |
| `install_hint` | Prints one line naming how an operator installs the tool. |

The dispatcher (`plugins/code-metrics/scripts/dispatch.sh`) resolves the ordered collector list per
lane and measure from `scripts/collector-ladder.tsv` (then the config override), calls `probe`
down the list, uses the first that resolves, and writes the `run[]` row either way; a ladder row
whose adapter file does not exist is `unavailable` with reason `adapter not shipped`. A collector
that probes but then produces no parseable output in `collect` produces exit `3` and a `run[]`
row with `status: unavailable` and the tool's stderr as `reason`, so a half-working tool is visible
rather than silent. Adapters for tools that write their report to a file (`jscpd` 5, a Rust
binary, writes `<output>/jscpd-report.json`) read that file and print it to stdout themselves.

Coverage is not a collector: `audit-coverage` reads artifacts through parsers
(`scripts/parsers/lcov.py`, `cobertura.py`, `coverage_py_json.py`, `go_cover.py`) that share one
interface, `parse(path) -> {file: {"lines": {line: hits}, "functions": [...] | None}}`, and it
never runs a test command.

Every shell entry point resolves its plugin root as
`PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"` (the
repository idiom), so suites and sanity checks work outside a Claude session.

## 4. Seams to other plugins (all presence-gated, all optional)

| Direction | Seam | Gate and fallback |
|---|---|---|
| out | `verification:measure metrics` (its `baseline` and `compare` phases) consumes this JSON | The audit skills mention it once: "feed this JSON to `/verification:measure metrics` when the `verification` plugin is installed, treating `status: empty` on either side as INCONCLUSIVE; otherwise keep the JSON beside your notes and compare by hand". |
| out | `mutation-testing`, `testing:audit`, `code-tidying:audit-dead-code`, `coupling:reduce`, `toolchain:lint` own the measures the Brief leaves with them | `principles` names each owner with an "if installed" gate and the fallback "the concern is out of this plugin's scope; nothing here substitutes for it". |
| in | The consumer's `.claude/ecosystems/<lane>.yaml` | A convention file, not a plugin; bundled extension map is the fallback. |
| in | The consumer's sanctioned-replication registry | Listed in config; absent means no exclusions. |
