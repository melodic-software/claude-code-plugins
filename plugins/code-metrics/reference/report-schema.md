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
| `status` | string | `complete` (every implied lane and measure ran), `partial` (at least one did not), `empty` (nothing was measured; the markdown headline reads "Measured nothing") |
| `scope` | object | `mode` (`change`, `paths`, `all`), `base` (the merge-base's short SHA under `change`, else `null`), `files` (count in scope), `unclassified` (how many of those belong to no lane, so `files` minus `unclassified` is the measured count), `excluded` (count dropped by scope exclusions) |
| `run` | array | The "Coverage of this run" table, one row per lane and measure the scope implied |
| `thresholds` | array | The references in force: `measure`, `reference` (number or `null`), `provenance`, `layer` (which config layer supplied it, or `bundled default`) |
| `measures` | array | The rows, see below |
| `summary` | object | `files`, `functions`, `over_reference` (measure name to count); when clone-group rows are present, `duplicated_lines` (sum of each group's `values.lines`, one group counted once, after registry exclusions) and `clone_groups` |
| `excluded` | array | Duplication only: clone groups dropped by a sanctioned-replication registry, each naming the registry path and line |
| `unavailable` | array | `lane/measure` strings for every `run` row whose status is `unavailable` |

## `run[]` rows

`lane`, `measure`, `collector` (the tool and version that produced the rows, or `null`), `status`
(`ok`, `unavailable`, `not-applicable`, `deferred`), `reason` (`null` only when `ok`). A run whose
scope holds no measurable file carries one row `*/*` with status `not-applicable` and the reason
`no measurable files in scope`.

## `measures[]` rows

Common fields: `file`, `function` (`null` for a per-file row), `lane`, `values` (measure name to
number or `null`), `collector`, `labels` (strings such as `comment-agnostic`), `over_reference`
(the measures whose reference the row is at or beyond). Granularity by skill:

| Skill | One row per | Extra fields |
|---|---|---|
| `audit-size` | file | none; in `iso-8.2.115` mode one row per function with `start_line`, `end_line` |
| `audit-complexity` | function (`start_line`, `end_line` when the collector reports them) | none |
| `audit-coverage` | function | `cov_source` (`artifact-region` or `line-range`), `hit` (the artifact's function-hit flag or `null`) |
| `audit-duplication` | clone group | `instances[]` (`file`, `start_line`, `end_line`) replaces `file` and `function` |
| `audit-type-debt` | lane | `file` and `function` are `null` |

A value the collector did not produce is `null`, never `0`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The document was produced, including an `empty` run |
| 2 | Usage error, including an explicitly named path, artifact, or registry that does not exist, or a missing Python 3.9 |
| 3 | A resolved collector ran and produced no parseable output; the document is still produced and the failure is in `run[]` |

## The reference semantics

A reference is a value to count against, never a bar. `over_reference` counts values at or above
the reference for most measures and below it for coverage and type coverage; a `null` reference
counts nothing. No finding, severity, or exit code follows from a count.
