# The code-metrics configuration

Every tunable value in this plugin resolves through one set of config layers. This document is their
contract: the layers, the merge form, the YAML subset, and every key with its default and
provenance. `/code-metrics:setup` writes the team layer; every audit skill reads the resolved
document at run time and prints the layer that supplied any value a personal layer changed. The
JSON Schema for every layer's keys is [`schemas/code-metrics.schema.json`](../schemas/code-metrics.schema.json).

## Layers and merge form

The surface follows the marketplace's config-cascade convention. Three layers, each optional,
resolved in this order over the bundled defaults (`scripts/config-defaults.json`):

| Order | Layer | Path | Belongs to |
|---|---|---|---|
| 1 | user-global | `~/.claude/code-metrics.yaml` | the operator, across repositories |
| 2 | team | `<repo>/docs/conventions/code-metrics.yaml` | the repository, tracked |
| 3 | personal override | `<repo>/.claude/code-metrics.local.yaml` | one operator in one repository, gitignored |

This plugin still reads, or reports as retired, the `.claude/` paths named here; until the plugin migrates, keep config where this page says it is read, then move it where [config locations](config-locations.md) says.

The team layer is `docs/conventions/code-metrics.yaml` alone. The team file earlier releases read
from the repository's `.claude/` directory is retired and never read. `/code-metrics:setup check`
reports it, and `/code-metrics:setup apply`, run while the docs file is absent, carries every
declared key of the retired file into the docs file in one write and drops and names any other
key; then delete the retired file.

**An invalid layer never stops the run.** A file outside the YAML subset is named with its line
and read as absent. A value of the wrong shape is named with its file, key and value, and that
layer's value is dropped: the key resolves from a valid higher layer, else the bundled default,
never from a lower layer. The wrong shapes the resolver drops: a scalar or `null` where a mapping
belongs, a scalar where a list belongs, a reference that is not a number or `null`, a key or value
holding a newline, carriage return or tab, a `scope.exclude` glob the matcher cannot compile, and a
`suppressions.correctness_rules` item that is not a string.

**Merge form: per-key override**, declared here because every value is a scalar or a closed list.
A later layer replaces an earlier layer's value key by key; a key absent from a later layer keeps
the earlier value; a list (`scope.exclude`, `lanes.<lane>.collectors.<measure>`) is a closed value
and is replaced whole, never concatenated. Unknown keys are inert. All three layers absent is
valid. The recommended consumer `.gitignore` line for the personal override is `.claude/**/*.local.*`; the
plugin never edits your `.gitignore`.

The consumer's `.claude/ecosystems/<lane>.yaml` files (the ecosystem-commands convention) resolve
through the same three layers for their `globs` (which replace the bundled extension map for that
lane) and `enabled` (a resolved `false` opts the lane out). Only a lane named under `lanes` reads
its file: the bundled lanes, plus any extra id a layer lists there. A record whose id is not listed
creates no lane, because a record need not describe a programming language (a lint-only
`markdown` or `yaml` record is common).

To add a lane the plugin does not ship, list its id under `lanes` and give it a record with
`globs`:

```yaml
# docs/conventions/code-metrics.yaml
lanes:
  rust:
    enabled: true
```

```yaml
# .claude/ecosystems/rust.yaml
globs: ["**/*.rs"]
```

The id must be lowercase kebab-case, the record's filename stem; any other id is dropped with a
warning. The files the globs match form the `rust` lane. With no shipped collector for it, every
measure on that lane reads `unavailable` with the reason `no shipped collector for the rust lane`,
except `file_lines`, which walks the `other` lane's collectors so the files keep their line count.

The user-global layer is looked up under `$HOME`; `CODE_METRICS_HOME`, when set, replaces that
directory for one run (the plugin's own suites use it to point at a scratch home, and a consumer
can use it the same way to try a personal layer without touching `~/.claude`). It is the only
environment variable the cascade reads; no key is settable from the environment.

## The YAML subset

The plugin reads YAML with a bundled parser for a documented subset, because the standard library
has no YAML parser and the plugin carries no third-party dependency. Inside the subset: block
mappings, block sequences, flow sequences of scalars (`["*.sh", "*.bash"]`), plain and quoted
scalars (`str`, `int`, `float`, `true`/`false`, `null`), and `#` comments. Outside it, reported
with the file and line and never parsed partially: flow mappings (`{ a: 1 }`), anchors and
aliases, tags, block scalars (`|`, `>`), document markers, tab indentation, and duplicate keys.
Every reference value is a number or `null`; a quoted number (`reference: "20"`) is a string
scalar, and the resolver drops it by file, key and value (a WARN `config` row in
`/code-metrics:setup check`) rather than letting an audit compare a number against it.

## Keys

The key column and the default column of this table are checked against
`scripts/config-defaults.json` on every change by
`scripts/check-code-metrics-config-reference.py`, so the two cannot disagree: a key added to,
removed from, or given a different default in that file fails the check until this table follows.
The third column is written by hand and is not derived from anything. A row whose key carries a
`<placeholder>` segment covers every key matching it, and a default written as the bare word
`absent` marks a key the defaults file deliberately does not default.

| Key | Default | Meaning and provenance |
|---|---|---|
| `scope.default` | `change` | `change` (the merge-base diff plus uncommitted and untracked files) or `all` |
| `scope.base` | `auto` | The merge-base is taken against the default branch, or against this ref |
| `scope.exclude` | `["**/node_modules/**", "**/vendor/**", "**/dist/**", "**/build/**"]` | Gitignore-style globs dropped from every measure. The default names dependency and build-output directories, because measuring a compiled bundle or a vendored tree counts functions nobody in the repository wrote; fixtures and evals stay in scope. A closed list, so a team file that sets it replaces the default whole (`[]` measures everything). The count is reported as `scope.excluded` and each pattern's count as `scope.exclusions[]` |
| `scope.registries` | `[]` | Sanctioned-replication registries, each relative to the repository root, applied by every audit. A plain line is one path-within-plugin, taken whole, spaces included: rows for a file it names collapse to one row carrying a replica count, and a clone is excluded, not suppressed, when every instance ends with that path and the copies sit in distinct carrying directories. A line `<canonical> -> <member>...` is a cluster line read by the duplication audit only: the root-relative canonical copy, then the paths or gitignore-style globs that carry it; a clone is excluded when every instance is the canonical or matches a member and the instances' directories are pairwise distinct. Instance paths are compared root-relative, and the first matching line in file order wins |
| `complexity.cyclomatic.reference` | `20` | ISO/IEC 5055:2021 §8.2.117 (normative). Cited alternatives: 10 (McCabe 1976, "reasonable, but not magical") and 15 (NIST SP 500-235, with its six practices) |
| `complexity.cognitive.reference` | `null` | Campbell, SonarSource; no standard sets a threshold |
| `complexity.halstead.difficulty` | `null` | Halstead 1977; no standard sets a threshold |
| `size.mode` | `file-lines` | `file-lines` compares each file's non-blank lines to `size.file_lines`; `iso-8.2.115` adds each function's non-empty lines as a percentage of the file's (the plugin's reading of the clause, which states 5% with no base), from a collector that reports function ranges |
| `size.file_lines` | `1000` | The plugin's own number. It coincides with an informative figure in ISO/IEC 5055:2021 §6.3 Table 1, which is not normative; 500 is selectable |
| `size.check` | `report` | What `audit-size.sh --check` fails, the size report's opt-in check mode. `report` fails nothing. `crossing` fails a changed file whose non-blank lines were below `size.file_lines` at the base and are at or above it now. `crossing-or-growth` also fails a file already at or above the reference at the base whose count grew; under `crossing` that file is listed and passes, as the review plugin's size-crossing note treats it. A file already over that did not grow never fails. The plugin's own design; any other value is a usage error |
| `size.function_lines_pct` | `5` | ISO/IEC 5055:2021 §8.2.115 (normative) states the 5%; the percentage-of-file base is the plugin's reading; used in `iso-8.2.115` mode |
| `duplication.min_tokens` | `50` | Passed to the clone collector |
| `duplication.min_lines` | `5` | Passed to the clone collector |
| `duplication.ignore` | `[]` | Collector ignore globs |
| `duplication.max_lines` | `null` | A file with more lines is left out of the clone scan and named in the lane's `partial` run row; `null` or `0` means the plugin sets no line cap; jscpd 5.x has none and 4.x defaults to 1000 lines, so the adapter passes a bound no file reaches (see the `jscpd size and line caps` row in [collectors.md](collectors.md#duplication)). A number is a plugin-local guard, not an upstream convention |
| `duplication.max_size` | `1mb` | A file larger than this is left out and named the same way; `0` means no cap; upstream guards are in [collectors.md](collectors.md#duplication-size-limits). `kb` and `mb` are binary (1mb is 1,048,576 bytes); a CRLF checkout counts one more byte per line |
| `duplication.rollup_depth` | `2` | A plain integer. A float, a quoted integer, or any other non-integer is a usage error that names the key and the value; it does not fall back to 2. Directory depth to which the markdown report lists per-directory rollup rows; the JSON carries every directory |
| `duplication.registries` | `[]` | The older name for `scope.registries`, read only when the scope-level list is empty; a team file written against it keeps working unchanged |
| `coverage.artifacts` | `[]` | Explicit coverage artifact paths; empty means auto-discover. An explicitly named path that does not exist is a usage error |
| `coverage.path_prefix_strip` | `[]` | Prefixes removed from artifact paths before the join with source paths (compiled-output layouts) |
| `coverage.reference` | `null` | No default bar; ISO/IEC 25023 files coverage under Reliability and sets no value |
| `coverage.crap.reference` | `null` | Savoia and Evans 2007; not a validated change-risk predictor |
| `type_debt.reference` | `null` | No standard or CWE anchors the measure |
| `suppressions.correctness_rules` | `[]` | Rule ids that guard correctness rather than style (for example `no-floating-promises`, `SC2086`, `CA2000`). `/code-metrics:audit-suppressions` marks every suppression that names one, compared case-insensitively, and counts them. A closed list, replaced whole. The plugin ships none: which rules guard correctness is the repository's call |
| `lanes.<lane>.enabled` | `true` | Opts a lane out even under `--all`; lanes are `typescript`, `python`, `bash`, `go`, `dotnet`, and `other`, the catch-all for every text file no language lane claims, which the ladder serves with `file_lines` alone, plus any extra id listed here (see the ecosystem files above) |
| `lanes.<lane>.collectors.<measure>` | absent | Replaces the bundled ordered collector list for that lane and measure; names are validated against `scripts/collector-ladder.tsv` and an unknown name is dropped with a warning. An empty list is a closed value like any other: no collector runs for that lane and measure, and the run row says so |

A `reference` of `null` means "report the value, count nothing"; a number counts values at or
above it (below it for coverage and type coverage) as `over_reference`. No finding, severity, or
exit code follows from either, except under `audit-size.sh --check` with `size.check` set to a
rule other than `report`.

A resolved `scope.default` of `all` and a resolved `scope.base` reach every audit entry point, so
a repository can make the tree the default. A command-line `--all`, `--base`, or explicit path
still wins over both.

## Example

```yaml
# docs/conventions/code-metrics.yaml
complexity:
  cyclomatic:
    reference: 15
size:
  file_lines: 500
scope:
  exclude: ["vendor/**", "generated/**"]
lanes:
  typescript:
    collectors:
      cyclomatic: [lizard]
  dotnet:
    enabled: false
```

## Reserved keys

`thresholds` and any key starting with `_` belong to the bundled defaults and the resolver's
output (`_layers`, `_provenance`, `_files`, `_ecosystems`, `_warnings`); a layer that sets them is
reported and the key ignored.
