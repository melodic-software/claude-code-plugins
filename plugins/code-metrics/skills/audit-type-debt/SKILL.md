---
description: "Measure how much of the code is typed for the changed files, a path, or the whole tree, per file and as a percentage per lane: `type-coverage`'s ratio of identifiers whose type is not `any` for TypeScript, and mypy's `--any-exprs-report` coverage over expressions for Python. Because no standard or CWE anchors this measure, the reference is `null` by design and the number is a trend to watch rather than a bar; the report emits no finding, severity, or exit-code gate. Bash and Go have no comparable collector, and C# is not applicable, because an occurrence count is not comparable to a ratio. A lane whose tool is absent says so with an install hint and the run continues. Use when: 'how much of this is typed', 'type coverage', 'how many anys are in this', 'any usage in the change', 'type debt', 'measure our typing', 'mypy any expressions report'; for cyclomatic or cognitive complexity use /code-metrics:audit-complexity, and for what a measure can and cannot say use /code-metrics:principles."
argument-hint: "[--json] [--all] [--base <ref>] [<path>...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/audit-type-debt.sh:*)", "Bash(git branch --show-current:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Typed-code percentage per file and per lane, with no standard behind it
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

"Get `any` and `unknown` to zero" is a goal without a yardstick: no standard and no CWE anchors a
typed-code percentage. This skill reports what the two tools that produce a real percentage
measure, per file and per lane, and says plainly where the number comes from and what it does not
mean. There is no pass or fail here, and no bar to argue with.

| Lane | Collector | Values | The number it reports |
|---|---|---|---|
| TypeScript/JavaScript | `type-coverage` | lane row: `type_coverage_pct`, `typed_identifiers`, `total_identifiers`, `any_count`; file row: `any_count` alone, the other three `null` | identifiers whose type is not `any`, over all identifiers |
| Python | mypy `--any-exprs-report` | `type_coverage_pct`, `any_expressions`, `expressions_total` on every file row and on the lane row | mypy's own Coverage column: expressions not typed `Any`, over all expressions |
| Bash | not applicable | | no collector reports a typed-code ratio for shell |
| Go | not applicable | | the compiler admits no untyped identifier to count |
| C# | not applicable | | no tool produces a comparable percentage for C#; a `dynamic`/`object` occurrence count is not comparable to a ratio |

## Run it

```bash
"${CLAUDE_SKILL_DIR}/scripts/audit-type-debt.sh"                    # the change: diff from the merge-base plus uncommitted files
"${CLAUDE_SKILL_DIR}/scripts/audit-type-debt.sh" src/ lib/api.py    # explicit paths (a missing one is a usage error)
"${CLAUDE_SKILL_DIR}/scripts/audit-type-debt.sh" --all              # every tracked or untracked-but-not-ignored file
"${CLAUDE_SKILL_DIR}/scripts/audit-type-debt.sh" --json --all src/  # the code-metrics/v1 document instead of markdown
```

Present the markdown report as printed. It opens with the scope and a "Coverage of this run" table
(lane, collector, status, reason), then the reference with its provenance and layer, then one row
per file, least typed first, and one row per lane labelled `lane-total`. Keep the `--json`
document when the numbers feed a comparison:
`/verification:measure metrics` consumes it when the `verification` plugin is installed (treat a
report whose `status` is `empty` on either side as INCONCLUSIVE); otherwise keep the JSON beside
your notes and compare by hand.

## Reading the numbers

- The two percentages are not the same measure. One counts identifiers, the other counts
  expressions, over different populations and from different type checkers. Read each against its
  own lane over time; never compare them with each other, and never average them.
- The reference is `null` by design, because no standard or CWE sets one. A consumer who sets one
  gets a `below` comparison (a lane under the reference is counted), which is still a count and
  never a finding, a severity, or an exit code.
- The `lane-total` row is the lane's figure and the summary's `Files:` count is the file rows.
  For Python the lane row is the sum of the file rows, so a change-scoped run reports the scope's
  own coverage rather than everything mypy followed. mypy names modules, not files; the file is
  recovered by re-deriving mypy's `--explicit-package-bases` naming from the path, and when none
  of its names matches a scope file (a `mypy_path` in the consumer's mypy config can do that) the
  lane row is mypy's own Total, no file row is emitted, and the run row's reason says so.
- A value the tool did not produce is `null`, never `0`: `any_count` is `null` when
  `type-coverage` listed no locations, and `type_coverage_pct` is `null` when nothing was counted
  at all (a TypeScript project with no `tsconfig.json` reaches this). A TypeScript file row
  carries `any_count` alone, the occurrences `type-coverage --detail` listed for that file,
  because the CLI gives no per-file denominator. A scope file in the project's `tsconfig.json`
  program with no listed occurrence reads `0`, a measured zero; a scope file outside that program
  gets no row and is counted in the run row's reason; when the lane counted nothing, no file row
  is emitted.
- mypy exits 1 on any type error and still writes its report; the rows are kept, the lane row is
  labelled `mypy-reported-errors`, and the run row's reason counts the errors and, among them,
  the missing stubs (`import-untyped`, `import-not-found`), which says how much of the `Any`
  count is unstubbed imports rather than local typing. A type error is not a missing measurement.
  mypy exits 2 when a blocking error (a duplicate module name, a usage or config error) stops it
  before analysis; the Python lane then reads `unavailable` with mypy's own message, never a
  percentage, and the run continues.
- Exit 0 whenever a report was produced, including a run that measured nothing; exit 2 for a usage
  error such as an explicitly named path that does not exist; exit 3 when a collector resolved but
  produced nothing parseable, with its stderr in the run table.

## Configuration

Everything tunable resolves through `.claude/code-metrics.yaml` (user-global, team, local overlay;
per-key override; keys in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`): the reference
(`type_debt.reference`, `null` by default), scope exclusions (`scope.exclude`), a per-lane opt-out
(`lanes.<lane>.enabled: false`, which drops that lane even under `--all`), and the per-lane
collector order (`lanes.<lane>.collectors.type_coverage`). The report names the layer that
supplied any value a personal layer changed. `/code-metrics:setup` writes the team file and probes
the collectors.

## What this skill does not do

- It does not run tests, edit files, add annotations, or install `type-coverage` or `mypy`; an
  absent tool is a row in the run table with its install hint.
- It does not judge: the reference is not a bar, and no `check` gate exists in this version.
- It does not count `any` occurrences for C#, and it does not report a count where the other lanes
  report a ratio.
- It does not measure complexity, size, duplication, or coverage; those are the sibling `audit-*`
  skills in this plugin, and `/code-metrics:principles` explains what each number means.

## Next

- The numbers feed a before-and-after comparison: `/verification:measure metrics`.
- A percentage is about to be read as a bar: `/code-metrics:principles`.

## Gotchas

- `type-coverage` needs a resolvable `typescript` in the project it runs against, and crashes
  without one, so the probe requires both and the lane reports `unavailable` with that reason when
  only the binary is present. Install both as project dev dependencies.
- `type-coverage` reads the project's `tsconfig.json`. Without one it counts nothing and reports
  `null` rather than a percentage.
- mypy lists only the files it was given, so the file rows and the lane row cover the scope files
  alone; it still follows their imports to type them, so a scope file's count can move when a
  module it imports changes with no edit to the file itself. Compare like-scoped runs.
- mypy names modules, not files. The collector re-derives the name mypy gives each scope path
  with the working directory as the base; a base the consumer's mypy config adds (`mypy_path =
  src`, the src layout) shortens mypy's names, which are then matched to the one scope file whose
  derived name ends in that name. A listed name that matches nothing is left out of the lane row
  and counted in the run row's reason, as is a scope file mypy listed nothing for.
- `type-coverage` counts only the files its `tsconfig.json` program holds and does not say which
  those are, so the collector reads the program through the project's own `typescript` (one
  `node` call) and gives a row only to scope files in it; a scope file outside the program is
  counted in the run row's reason, never reported as 0. When that call fails, only scope files
  with a listed occurrence get a row and the reason says why.
- The Python percentage moves when a dependency ships or drops type stubs, because an unfollowed
  import turns into `Any`. A drop with no local edit is usually that.
- mypy runs with `--explicit-package-bases`, so a file vendored into several plugins (sanctioned
  replication) is named by its path (`plugins.a.lib.x`) and measured once per copy instead of
  aborting the lane. mypy's module walk stops at a directory whose name is not a Python
  identifier, so two same-named files under two hyphenated directories (`my-pkg/mod.py`,
  `other-pkg/mod.py`) still collide; that run reads `unavailable` with the duplicate-module
  message. mypy accepts the flag only while namespace packages are on (its default), so a
  consumer config that turns them off makes the run repeat without it, in mypy's own naming
  (packages from `__init__.py` files), and the run row's reason says so; same-named files collide
  again in that mode.
- mypy runs with its cache disabled (`--cache-dir` set to the platform's null device), so no
  `.mypy_cache/` is written into the working tree. A one-shot report gains nothing from the cache.
