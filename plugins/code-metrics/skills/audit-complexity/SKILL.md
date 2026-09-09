---
description: "Measure per-function cyclomatic and cognitive complexity and Halstead difficulty for a change, a path, or the tree, per lane (TypeScript/JavaScript, Python, Bash, Go; C# deferred), from whichever external collector already resolves (lizard, radon, ESLint, sonarjs, gocyclo, gocognit, shellmetrics, multimetric); it installs none. Each number cites its reference: cyclomatic 20 from ISO/IEC 5055:2021 §8.2.117, with 10 (McCabe 1976) and 15 (NIST SP 500-235) selectable; cognitive (Campbell, SonarSource) and Halstead (Halstead 1977) carry none, no standard setting one. A lane with no collector says so and the run continues, an unmeasured value is null not zero, and no finding, severity, or exit-code gate is emitted. Use when: 'how complex is this code', 'cyclomatic complexity', 'cognitive complexity', 'complexity audit', 'is this function too complex', 'Halstead difficulty', 'measure complexity of a change'; for lines per file use /code-metrics:audit-size."
argument-hint: "[--json] [--all] [--base <ref>] [<path>...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/audit-complexity.sh:*)", "Bash(git branch --show-current:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Per-function complexity beside a cited reference, no verdict
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Complexity is the measure with the most citable reference on the operator's list and the most
folklore around it. This skill reports the numbers, per function where the collector reports per
function, beside references whose provenance is printed with them, and stops there: no pass or
fail, no severity, no finding. Whether a complexity of 23 is worth changing is the reader's call.

Collectors are tried in order per lane and the first that resolves is used. Nothing is installed,
downloaded, or fetched at run time; a lane with no resolvable collector reports that in the run
table and the other lanes still run.

| Lane | Cyclomatic | Cognitive | Halstead difficulty |
|---|---|---|---|
| TypeScript/JavaScript | `lizard`, then ESLint's core `complexity` rule | `eslint-plugin-sonarjs` | `multimetric`, per file |
| Python | `lizard`, then `radon cc -j` | no maintained collector found; the row says so | `radon hal -j`, per function, then `multimetric` |
| Bash | `shellmetrics`, then `multimetric` | no collector found; the row says so | `multimetric`, per file |
| Go | `lizard`, then `gocyclo` | `gocognit` | `multimetric`, per file |
| C# | deferred | deferred | deferred |

`lizard` and `radon` report a start and an end line per function; `gocyclo`, `gocognit`,
`shellmetrics`, and the two ESLint rules report a start line only, and their rows are labelled
`start-line-only`. `multimetric` has no per-function granularity at all, so its rows are per file,
carry `function: null`, and are labelled `file-level`. Its Bash cyclomatic figure is labelled
`multimetric-approximation` because it under-counts against a per-function parser.

## Run it

```bash
"${CLAUDE_SKILL_DIR}/scripts/audit-complexity.sh"                    # the change: merge-base diff plus uncommitted files
"${CLAUDE_SKILL_DIR}/scripts/audit-complexity.sh" src/ lib/parse.py  # explicit paths (a missing one is a usage error)
"${CLAUDE_SKILL_DIR}/scripts/audit-complexity.sh" --all              # every tracked or untracked-but-not-ignored file
"${CLAUDE_SKILL_DIR}/scripts/audit-complexity.sh" --json --all src/  # the code-metrics/v1 document instead of markdown
```

Present the markdown report to the user as printed. It opens with the scope and a "Coverage of
this run" table (lane, measure, collector, status, reason), then the references with their
provenance and layer, then one row per function or file: every collector's numbers for a function
sit on that one line, a Labels column carries `start-line-only`, `file-level`, and
`multimetric-approximation` where they apply, and rows over a reference come first, the furthest
past it at the top. The table stops at 200 rows; its last line and the summary name the file the
whole `code-metrics/v1` document was written to (under `CLAUDE_PLUGIN_DATA`, else
`~/.claude/plugins/data/code-metrics/reports`), so the numbers past the cap are on disk without a
second run. Pass that document, or a `--json` run's output, to `/verification:measure metrics`
when the `verification` plugin is installed, treating `status: empty` on either side as
INCONCLUSIVE; otherwise keep it beside your notes and compare by hand.

## Reading the numbers

- A reference is a value to count against, never a bar. Rows at or above it are listed in
  `over_reference` and counted in the summary; nothing else follows from that.
- Cyclomatic complexity ships a reference of 20, from ISO/IEC 5055:2021 §8.2.117, which is
  normative. Two documented alternatives are selectable through
  `complexity.cyclomatic.reference`: 10, from McCabe 1976, who called it "reasonable, but not
  magical", and 15, from NIST SP 500-235, which pairs it with six practices rather than using it
  alone.
- Cognitive complexity (Campbell, SonarSource) and Halstead difficulty (Halstead 1977) ship no
  reference, because no standard sets one for either. Setting `complexity.cognitive.reference` or
  `complexity.halstead.difficulty` makes the report count against your own number, labelled with
  the layer that supplied it.
- A `null` value means the resolved collector did not produce that number for that row. It is
  never zero, and a zero in the report is a measurement: a Halstead difficulty of 0 is a function
  in which the collector found no operators or operands, and the table says so under it.
- A row marked `replicated` stands for every copy of a file the repository's
  sanctioned-replication registry names (`scope.registries`), with the copy count beside the
  path; the copies were measured, the function is shown once, and the over-reference count
  counts it once.
- An empty change scope is reported with its cause: the branch sits at its merge-base with a
  clean tree, or the changed files belong to no lane. Explicit paths or `--all` measure the tree.
- `status` is `complete` when every lane and measure in scope ran, `partial` when one did not, and
  `empty` when nothing was measured; the run table says why for every non-`ok` row.
- Exit 0 whenever a report was produced, including an `empty` one; exit 2 for a usage error such
  as an explicitly named path that does not exist; exit 3 when a collector resolved but produced
  nothing parseable, with its stderr in the run table.

`/code-metrics:principles` is where the measures are defined, what each one can and cannot tell
you, and why no threshold here is a verdict.

## Configuration

Everything tunable resolves through `.claude/code-metrics.yaml` (user-global, team, local
overlay; per-key override; keys in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`): the three
references above, scope exclusions (`scope.exclude`, which by default drops `node_modules`,
`vendor`, `dist`, and `build` directories at any depth and reports each pattern's count),
sanctioned-replication registries (`scope.registries`), the base ref (`scope.base`), and the
per-lane collector order (`lanes.<lane>.collectors.<measure>`, validated against
`${CLAUDE_PLUGIN_ROOT}/scripts/collector-ladder.tsv`). The report names the layer that supplied
any value a personal layer changed. `/code-metrics:setup` writes the team file and probes the
collectors.

A whole-tree run launches one collector process per lane and measure in parallel, capped at the
CPU count or `CODE_METRICS_JOBS`, and prints a progress line per collector on stderr once the
scope passes a few hundred files (`CODE_METRICS_PROGRESS=1` forces it, `=0` silences it). Its
wall clock is the slowest collector's own, which the plugin does not control.

## What this skill does not do

- It does not install a collector, run tests, or edit files. A missing collector is reported with
  its install hint and the run continues.
- It does not judge. No reference here is a bar, no finding or severity is emitted, and this
  version ships no `check` gate.
- It does not compute CRAP: that needs coverage, and `/code-metrics:audit-coverage` computes it by
  joining this skill's per-function numbers with a coverage artifact.
- It does not measure lines, duplication, coverage, or type debt; those are the sibling `audit-*`
  skills in this plugin.

## Next

- The numbers feed a before-and-after comparison: `/verification:measure metrics`.
- A complex function's coverage and CRAP score are the real question:
  `/code-metrics:audit-coverage`.
- A number is about to be quoted at someone: `/code-metrics:principles`.

## Gotchas

- The two ESLint-based rungs resolve only when the repository already wires ESLint (`eslint` on
  `PATH` or in `node_modules/.bin`, and an `eslint.config.*` from the working directory upward,
  since ESLint 9 and later load nothing else), and the cognitive rung also needs
  `eslint-plugin-sonarjs` in `node_modules`. Otherwise the row is `unavailable` with that
  reason; `lizard` still covers TypeScript cyclomatic complexity.
- `multimetric` and `gocognit` have no version flag. The run table carries the version their
  package metadata or `go version -m` reports, and reads `version unavailable` when neither
  answers, so two reports can still be compared by tool.
- Python and Bash have no maintained cognitive-complexity collector, so those rows read
  `unavailable` with that reason rather than reporting a substitute measure. The claim, what it
  rests on, when it was checked, and what should send you to check again are recorded in
  [`${CLAUDE_PLUGIN_ROOT}/reference/collectors.md`](../../reference/collectors.md).
- Halstead outside Python is per file, so a file's difficulty is not a function's. Python is the
  only lane with per-function Halstead, and even there the rows carry no line range.
- A collector that reports only a start line cannot bound a function's lines, so `audit-coverage`
  reports `crap: not-applicable` for that lane rather than a null. In this version Bash has no
  collector with end lines at all.
- Change scope needs a merge-base with the default branch; outside a git repository, or on a
  branch with no default-branch ancestor, pass paths or `--all` (the usage error says which).
- Cyclomatic counts from different collectors are not interchangeable: the run table names the
  tool and its version for every row so two reports can be compared honestly.
