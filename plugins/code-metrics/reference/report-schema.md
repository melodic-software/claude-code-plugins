# The `code-metrics/v1` report

Every audit skill in this plugin prints exactly one JSON document on stdout (its `audit-size.sh --json`)
and renders markdown from it; diagnostics go to stderr. The document is the seam other tools
read, so its shape is stable within the `v1` schema string.

## Top level

| Field | Type | Meaning |
|---|---|---|
| `schema` | string | `code-metrics/v1` |
| `skill` | string | The producing skill, for example `audit-size` |
| `generated_at` | string | UTC timestamp, `YYYY-MM-DDTHH:MM:SSZ` |
| `status` | string | `complete` (every implied lane and measure ran; a `not-applicable` row implies nothing and never withholds it), `partial` (at least one `unavailable`, `deferred`, or `partial` row), `empty` (nothing was measured; the markdown headline reads "Measured nothing") |
| `scope` | object | `mode` (`change`, `paths`, `all`), `base` (the merge-base's short SHA under `change`, else `null`), `files` (count in scope), `unclassified` (how many of those belong to no lane, so `files` minus `unclassified` is the measured count; with the catch-all `other` lane enabled this is a disabled lane's files, and otherwise 0), `excluded` (count dropped by scope exclusions), `exclusions` (one `{pattern, files}` per `scope.exclude` glob that matched at least one file; a file two globs match counts under both) |
| `run` | array | The "Coverage of this run" table, one row per lane and measure the scope implied |
| `thresholds` | array | The references in force: `measure`, `value_key` (the `values` key the reference is applied to), `direction` (`at_or_above`, or `below` for coverage and type coverage), `reference` (number or `null`), `provenance`, `layer` (which config layer supplied it, or `bundled default`). The markdown Measures table lists rows over a reference first, furthest past it at the top, then the rest by the first entry whose `value_key` the rows carry, largest first (smallest first under `below`), and its 200-row cap names that key |
| `measures` | array | The rows, see below |
| `summary` | object | `files`, `functions`, `over_reference` (measure name to count); when clone-group rows are present, `duplicated_lines` (sum of each group's `values.lines`, one group counted once, after registry exclusions) and `clone_groups` |
| `excluded` | array | Duplication only: clone groups dropped by a sanctioned-replication registry, each naming the registry path and line |
| `unavailable` | array | `lane/measure` strings for every `run` row whose status is `unavailable` |

`summary.functions` counts functions, not rows: one function measured by two collectors produces two
rows and counts once. Rows are grouped by file and name, and a group counts as many functions as it
has distinct `start_line` values, or as one when no row in it reports a start line. So two `render`
methods in one file count as two, while a cyclomatic row and a Halstead row for the same function
count as one even though only the first reports where it begins. `summary.files` counts every
file a row stands for, the copies behind a `replicas` row included.

The markdown rendering joins the rows the same way the count does: one line per function with
every collector's values, a row with no start line joining the one function of its name in the
file, and never two rows whose values disagree. The JSON keeps one row per collector, because each
row names the tool that produced it.

## Sanctioned replication

When the resolved `scope.registries` names a registry (one path-within-plugin per line), the
per-file and per-function rows for every copy of a listed file that carry the same function, line
range, collector, lane, and values collapse into one row: the first by path, with the label
`replicated` and a `replicas` object (`count`, the files the row stands for including itself;
`registry`; `line`; `path`, the registry line's text; `files`). Rows whose values differ are
different files whatever the registry says, and all of them stay. Clone-group rows are
`audit-duplication`'s own pass and go to `excluded[]` instead.

## `run[]` rows

`lane`, `measure`, `collector` (the tool and version that produced the rows, or `null`), `status`
(`ok`, `partial`, `unavailable`, `not-applicable`, `deferred`), `reason` (`null` only when `ok` and
the collector said nothing; an `ok` row whose collector wrote to stderr while succeeding carries
that text, such as mypy's `mypy reported 386 errors (349 missing stubs)`). A
run whose scope holds no measurable file carries one row `*/*` with status `not-applicable` and a
reason that opens with `no measurable files in scope` and, under `change`, says why: the branch is
at its merge-base with a clean working tree (naming the ref and the `--all` alternative), or the
changed files belong to no lane. The lane `other` (every text file outside the language lanes)
has `file_lines` rows only; each other measure carries a `not-applicable` row for it.

`partial` means the row produced measurements for some of what it implied and not the rest, which
`audit-coverage` emits when an artifact covers only some of a lane's scope files, and again when it
left a function unjoined, naming those functions in the reason. It counts as having produced rows,
so such a run is `partial` rather than `empty`, and it withholds `complete`, so a document can never
read as complete while one of its own rows says `N of M`.

## `measures[]` rows

Common fields: `file`, `function` (`null` for a per-file row), `lane`, `values` (measure name to
number or `null`), `collector`, `labels` (strings such as `comment-agnostic`, `start-line-only`,
`file-level`, `replicated`, `lane-total`), `over_reference` (the measures whose reference the row is at or
beyond), and `replicas` on a collapsed row only (see "Sanctioned replication"). Granularity by
skill:

| Skill | One row per | Extra fields |
|---|---|---|
| `audit-size` | file | none; in `iso-8.2.115` mode one row per function with `start_line`, `end_line` |
| `audit-complexity` | function (`start_line`, `end_line` when the collector reports them) | none |
| `audit-coverage` | function | `cov_source` (`artifact-region`, `line-range`, `statement-ratio`, or `ambiguous`), `hit` (the artifact's function-hit flag or `null`), `reason` (why the join was refused; present only on an `ambiguous` row) |
| `audit-duplication` | clone group | `instances[]` (`file`, `start_line`, `end_line`) replaces `file` and `function` |
| `audit-type-debt` | file | one row per scope file the tool listed (`function` is `null`) plus one lane row per lane with `file` `null` and the label `lane-total`. The Python lane row sums its file rows, so a change-scoped run reports the scope's own coverage; when no listed module matched a scope file it is mypy's own Total and no file row is emitted. A TypeScript file row carries `any_count` alone (the occurrences `type-coverage --detail` listed for that file; the CLI gives no per-file denominator) with the other three values `null`, and the lane row carries all four |

A value the collector did not produce is `null`, never `0`.

A Go cover profile is the one artifact that gives no line table. Its blocks are statement counts
over line ranges and never say which lines hold the statements, so a file it covers takes
`coverage_pct` from the statement ratio, which is the number `go tool cover -func` prints, carries
`cov_source: statement-ratio` to say so, and reports `lines_executable` and `lines_hit` as `null`:
those two count lines, and the artifact counted something else.

That ratio is the file's exact native measure, so it outranks a line table for the same file: an
lcov or Cobertura artifact naming a `.go` file the profile also covers does not take
`coverage_pct` from it, and the line counts stay `null` there too, because a line ratio printed
beside a statement percentage reads as the two counts behind it and is a different measure. Both
formats still appear in the lane's `collector`, so nothing about the merge is hidden. A file no
statement-weighted artifact covers reports `cov_source: artifact-region` and its own line counts.

A Go function row reports `coverage_pct` and `crap` as `null`, because the profile names no
functions and attributing the file's ratio to each of them would be a number the artifact never
gave. Its `lines_executable` and `lines_hit` are `null` for the same reason, distinct from the `0`
a line-measuring artifact earns when it covers the file and carries no executable line in that
function's range.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The document was produced, including an `empty` run |
| 2 | Usage error, including an explicitly named path, artifact, or registry that does not exist, or a missing Python 3.9 |
| 3 | A resolved collector ran and produced no parseable output; the document is still produced and the failure is in `run[]` |

An adapter's own `collect` exits 4 when its tool resolved but cannot run in this repository at
all (ESLint reporting that it found no configuration for the files). That is not a run failure:
the entry script exits 0, and the lane's run row reads `unavailable` with the tool's own reason.

## The reference semantics

A reference is a value to count against, never a bar. `over_reference` counts values at or above
the reference for most measures and below it for coverage and type coverage; a `null` reference
counts nothing. No finding, severity, or exit code follows from a count.
