# Design resolution: code-metrics audit-duplication fixes

outcome: early-exit
tier: B (light design: localized contract additions inside one plugin, no new module, no topology change)
resolved: 2026-09-11, by the interview (two rounds) and five verified research runs

## Why early-exit

Every contract this change adds is an additive extension of a shape the plugin already has, and
the interview locked each one with its rationale and sources. No thread is open that a design
session would resolve differently from the Brief. The type sketch below is what an implementer
needs; `/planning:plan` consumes it.

## Type sketch

### Registry line grammar (extends `registry-filter.py`)

```text
line        := comment | blank | single | cluster
single      := path-within-plugin                       # unchanged meaning
cluster     := canonical-path SP+ member (SP+ member)*  # two or more whitespace-separated tokens
member      := repo-relative path | glob (pathglob.py syntax)
```

A group is excluded by a `cluster` line when every instance's repo-relative path matches the
canonical path or one member, and the instances sit in distinct carrying directories (the prefix in
front of the matched token; the canonical path's carrying directory is its own parent). The
`excluded[]` record keeps `{registry, line, path, instances}` with `path` = the line's text.

### Clone-group row after clustering (unchanged schema, N instances)

```json
{"file": null, "function": null, "lane": "bash",
 "instances": [{"file": "...", "start_line": 1, "end_line": 3136}, "... N entries"],
 "values": {"lines": 3136, "tokens": 25137},
 "collector": "jscpd", "labels": ["token-based", "clustered"]}
```

Merge key: two pair rows join when they share an instance with identical `(file, start_line,
end_line)` and equal `values.lines`. Union-find over all pair rows; `tokens` taken from the first
pair. Rows from `dupl` and `cpd` pass through untouched (already N-ary).

### Run row for a cap-skipped lane

```json
{"lane": "bash", "measure": "duplication", "collector": "jscpd 4.3.0", "status": "partial",
 "reason": "3 of 412 files skipped by duplication.max_size 1mb / max_lines none; largest: lib/x.sh (2.1mb)"}
```

Adapter to dispatcher channel: the adapter writes the skip note to the path in
`CODE_METRICS_RUN_NOTE_FILE` (set by `dispatch.sh` per lane/measure/tool); when the file is
non-empty after a successful collect, `dispatch.sh` writes the run row as `partial` with that text.
When the pre-filter leaves zero files, the adapter writes the note and exits 0 without invoking the
tool; the row is `partial` and no `exit 3` occurs.

### Summary additions (additive `code-metrics/v1`)

```json
"summary": {"files": 432, "functions": 0, "over_reference": {},
            "duplicated_lines": 16498, "clone_groups": 705,
            "by_lane": {"bash": {"groups": 380, "duplicated_lines": 12450}, "...": {}},
            "by_directory": {"plugins/code-metrics": {"groups": 127, "duplicated_lines": 1867}, "...": {}}}
```

`by_directory` keys are every ancestor directory of a group's first instance up to the root
(cumulative), rendered in markdown to `duplication.rollup_depth` (default 2). Both maps are
computed from surviving groups, after registry exclusion. Readers ignore unknown keys (stated in
`reference/report-schema.md`).

### Configuration keys (`config-defaults.json`, `reference/config.md`, setup template)

```yaml
duplication:
  min_tokens: 50
  min_lines: 5
  ignore: []
  registries: []
  max_lines: null      # no line cap; a number is a plugin-local guard
  max_size: 1mb        # jscpd 5.0.7 parser guard; SonarJS 1000kb generated-code rule
  rollup_depth: 2
```

Exported to adapters as `CODE_METRICS_DUP_MAX_LINES` (empty when null) and
`CODE_METRICS_DUP_MAX_SIZE`; the jscpd adapter passes both explicitly on every major, translating a
null line cap to a large explicit value on 4.x (whose `0` means "use the 1000 default") and never
emitting `--max-size 0`.
