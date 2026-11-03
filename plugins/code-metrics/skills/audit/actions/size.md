# Size

Lines per file is the one measure on the operator's list with a crisp definition and no
standard-backed file-level threshold. This action reports the number, per file in the scope,
beside a reference whose provenance is printed with it, and stops there: no pass or fail, no
severity, no finding. Deciding what to do with a long file is the reader's call; the report gives
them the number and the citation.

Two collectors, tried in order:

| Collector | Values per file | When |
|---|---|---|
| `scc` | `lines_total`, `lines_blank`, `lines_comment`, `lines_code`, `lines_non_blank` | `scc` resolves on `PATH` |
| bundled counter | `lines_total`, `lines_blank`, `lines_non_blank`, labeled `comment-agnostic` | always |

`scc` is used for line counting only; its complexity figure is never read, because it is a
substring count rather than cyclomatic complexity.

Every text file in scope is measured. The language lanes (TypeScript/JavaScript, Python, Bash,
Go, C#) are detected by extension, and everything else that is not binary (markdown, JSON, YAML,
PowerShell, a `Makefile`) lands in the catch-all `other` lane, which this measure serves and no
other does; `lanes.other.enabled: false` opts it out.

## Run it

```bash
"<skill-dir>/scripts/audit-size.sh"                      # the change: diff from the merge-base plus uncommitted files
"<skill-dir>/scripts/audit-size.sh" src/ lib/util.py     # explicit paths (a missing one is a usage error)
"<skill-dir>/scripts/audit-size.sh" --all                # every tracked or untracked-but-not-ignored file
"<skill-dir>/scripts/audit-size.sh" --json --all src/    # the code-metrics/v2 document instead of markdown
```

Present the markdown report to the user as printed. It opens with the scope and a "Coverage of
this run" table (lane, collector, status, reason), then the reference with its provenance and
layer, then one row per file, longest first by `lines_non_blank`, with its values and whether it
is at or above the reference. Keep
the `--json` document when the numbers feed a comparison: `/verification:measure metrics` consumes
it when the `verification` plugin is installed (treat a report whose `status` is `empty` on either
side as INCONCLUSIVE); otherwise keep the JSON beside your notes and compare by hand.

## Reading the numbers

- The reference compares against `lines_non_blank`. The bundled default is 1000, and its
  provenance is the one sentence the report prints beside it: the plugin's own number, not
  ISO-backed: it coincides with the informative figure in ISO/IEC 5055:2021 §6.3 Table 1, which is
  not normative, while the normative form (§8.2.115) is a function-level percentage; 500 is
  selectable; size.mode iso-8.2.115 selects the normative function-percentage alternative.
- A `null` value means the collector did not produce it (the bundled counter has no comment
  count); it is never zero.
- `status` is `complete` when every lane in scope was measured, `partial` when one was not, and
  `empty` when nothing was; the "Coverage of this run" table says why for every non-`ok` row.
- Exit 0 whenever a report was produced, including an `empty` one; exit 2 for a usage error such
  as an explicitly named path that does not exist; exit 3 when `scc` resolved but produced nothing
  parseable, with its stderr in the run table.

## Configuration

Everything tunable resolves through the code-metrics layers (user-global, team
`docs/conventions/code-metrics.yaml`, local overlay; per-key override; keys in `<plugin-root>/reference/config.md`): the reference
(`size.file_lines`), the mode (`size.mode`: `file-lines`, or `iso-8.2.115`, which adds a
`function_lines` measure comparing each function's non-empty lines against
`size.function_lines_pct` of the file's, from a collector that reports function ranges such as
`lizard` or `radon`; Bash has none and its row says so), scope exclusions (`scope.exclude`), and
per-lane collector order. The report names the layer that supplied any value a personal layer
changed. `/code-metrics:setup` writes the team file and probes the collectors.

## What this action does not do

- It does not run tests, edit files, or install `scc`; when `scc` is absent the run table says so
  and the bundled counter answers.
- It does not judge: no threshold here is a bar, and no `check` gate exists in this version.
- It does not measure complexity, duplication, coverage, or type debt; those are the sibling
  `audit` actions and `audit-*` skills in this plugin, and `/code-metrics:principles` explains
  what each number can and cannot tell you.

## Gotchas

- Change scope needs a merge-base with the default branch; outside a git repository, or on a
  branch with no default-branch ancestor, pass paths or `--all` (the usage error says which). A
  branch with nothing changed measures nothing, and the report's headline says so and how to
  widen the scope.
- `--all` on a large tree counts every tracked and untracked-but-not-ignored file; the report
  caps the rendered table at the 200 longest files and says how many more are in the JSON.
- `scc` counts comment lines by language, so a language it does not know is counted as code;
  the bundled counter is comment-agnostic by construction and says so in every row's `labels`.
