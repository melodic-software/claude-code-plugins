# The `.claude/code-metrics.yaml` configuration surface

Every tunable value in this plugin resolves through one consumer surface. This document is its
contract: the layers, the merge form, the YAML subset, and every key with its default and
provenance. `/code-metrics:setup` writes the team layer; every audit skill reads the resolved
document at run time and prints the layer that supplied any value a personal layer changed.

## Layers and merge form

The surface follows the marketplace's config-cascade convention. Three layers, each optional,
resolved in this order over the bundled defaults (`scripts/config-defaults.json`):

| Order | Layer | Path | Belongs to |
|---|---|---|---|
| 1 | user-global | `~/.claude/code-metrics.yaml` | the operator, across repositories |
| 2 | team | `<repo>/.claude/code-metrics.yaml` | the repository, tracked |
| 3 | local overlay | `<repo>/.claude/code-metrics.local.yaml` | one operator in one repository, gitignored |

**Merge form: per-key override**, declared here because every value is a scalar or a closed list.
A later layer replaces an earlier layer's value key by key; a key absent from a later layer keeps
the earlier value; a list (`scope.exclude`, `lanes.<lane>.collectors.<measure>`) is a closed value
and is replaced whole, never concatenated. Unknown keys are inert. All three layers absent is
valid. The recommended consumer `.gitignore` line for the overlay is `.claude/**/*.local.*`; the
plugin never edits your `.gitignore`.

The consumer's `.claude/ecosystems/<lane>.yaml` files (the ecosystem-commands convention) resolve
through the same three layers for their `globs` (which replace the bundled extension map for that
lane) and `enabled` (a resolved `false` opts the lane out).

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
scalar, and the resolver refuses it by key and layer (exit 2, and a FAIL `config` row in
`/code-metrics:setup check`) rather than letting an audit compare a number against it.

## Keys

| Key | Default | Meaning and provenance |
|---|---|---|
| `scope.default` | `change` | `change` (the merge-base diff plus uncommitted and untracked files) or `all` |
| `scope.base` | `auto` | The merge-base is taken against the default branch, or against this ref |
| `scope.exclude` | `[]` | Gitignore-style globs dropped from every measure; the count is reported as `scope.excluded` |
| `complexity.cyclomatic.reference` | `20` | ISO/IEC 5055:2021 §8.2.117 (normative). Cited alternatives: 10 (McCabe 1976, "reasonable, but not magical") and 15 (NIST SP 500-235, with its six practices) |
| `complexity.cognitive.reference` | `null` | Campbell, SonarSource; no standard sets a threshold |
| `complexity.halstead.difficulty` | `null` | Halstead 1977; no standard sets a threshold |
| `size.mode` | `file-lines` | `file-lines` compares each file's non-blank lines to `size.file_lines`; `iso-8.2.115` adds each function's non-empty lines as a percentage of the file's, from a collector that reports function ranges |
| `size.file_lines` | `1000` | The plugin's own number. It coincides with an informative figure in ISO/IEC 5055:2021 §6.3 Table 1, which is not normative; 500, the operator-list figure, is selectable |
| `size.function_lines_pct` | `5` | ISO/IEC 5055:2021 §8.2.115 (normative), used in `iso-8.2.115` mode |
| `duplication.min_tokens` | `50` | Passed to the clone collector |
| `duplication.min_lines` | `5` | Passed to the clone collector |
| `duplication.ignore` | `[]` | Collector ignore globs |
| `duplication.registries` | `[]` | Sanctioned-replication registries (one path-within-plugin per line); a clone whose every instance sits at a listed path is excluded, not suppressed |
| `coverage.artifacts` | `[]` | Explicit coverage artifact paths; empty means auto-discover. An explicitly named path that does not exist is a usage error |
| `coverage.path_prefix_strip` | `[]` | Prefixes removed from artifact paths before the join with source paths (compiled-output layouts) |
| `coverage.reference` | `null` | No default bar; ISO/IEC 25023 files coverage under Reliability and sets no value |
| `coverage.crap.reference` | `null` | Savoia and Evans 2007; not a validated change-risk predictor |
| `type_debt.reference` | `null` | No standard or CWE anchors the measure |
| `lanes.<lane>.enabled` | `true` | Opts a lane out even under `--all`; lanes are `typescript`, `python`, `bash`, `go`, `dotnet` |
| `lanes.<lane>.collectors.<measure>` | absent | Replaces the bundled ordered collector list for that lane and measure; names are validated against `scripts/collector-ladder.tsv` and an unknown name is dropped with a warning |

A `reference` of `null` means "report the value, count nothing"; a number counts values at or
above it (below it for coverage and type coverage) as `over_reference`. No finding, severity, or
exit code follows from either.

## Example

```yaml
# .claude/code-metrics.yaml
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
