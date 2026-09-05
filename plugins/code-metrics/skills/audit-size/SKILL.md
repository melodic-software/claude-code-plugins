---
description: "Measure lines per file for the changed files, a path, or the whole tree: total, blank, comment, and code lines when `scc` resolves, total and non-blank lines from a bundled counter otherwise, per lane (TypeScript/JavaScript, Python, Bash, Go; C# files are counted too). Each file is reported beside a configurable reference with its provenance (default 1000 non-blank lines, the plugin's own number and not ISO-backed; 500 selectable; an ISO/IEC 5055 §8.2.115 function-percentage mode selectable), and the report never emits a finding, a severity, or an exit-code gate. Use when: 'how long are these files', 'lines per file', 'file size audit', 'which files are too big', 'LOC per file', 'is this file over 1000 lines', 'count lines in the change'; for cyclomatic or cognitive complexity use /code-metrics:audit-complexity, and for a repo-wide dashboard this is the wrong tool (it measures a change)."
argument-hint: "[--json] [--all] [--base <ref>] [<path>...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/audit-size.sh:*)", "Bash(git branch --show-current:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Lines per file beside a cited reference, no verdict
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Lines per file is the one measure on the operator's list with a crisp definition and no
standard-backed file-level threshold. This skill reports the number, per file in the scope, beside
a reference whose provenance is printed with it, and stops there: no pass or fail, no severity, no
finding. Deciding what to do with a long file is the reader's call; the report gives them the
number and the citation.

Two collectors, tried in order:

| Collector | Values per file | When |
|---|---|---|
| `scc` | `lines_total`, `lines_blank`, `lines_comment`, `lines_code`, `lines_non_blank` | `scc` resolves on `PATH` |
| bundled counter | `lines_total`, `lines_blank`, `lines_non_blank`, labelled `comment-agnostic` | always |

`scc` is used for line counting only; its complexity figure is never read, because it is a
substring count rather than cyclomatic complexity.

## Run it

```bash
"${CLAUDE_SKILL_DIR}/scripts/audit-size.sh"                      # the change: diff from the merge-base plus uncommitted files
"${CLAUDE_SKILL_DIR}/scripts/audit-size.sh" src/ lib/util.py     # explicit paths (a missing one is a usage error)
"${CLAUDE_SKILL_DIR}/scripts/audit-size.sh" --all                # every tracked or untracked-but-not-ignored file
"${CLAUDE_SKILL_DIR}/scripts/audit-size.sh" --json --all src/    # the code-metrics/v1 document instead of markdown
```

Present the markdown report to the user as printed. It opens with the scope and a "Coverage of
this run" table (lane, collector, status, reason), then the reference with its provenance and
layer, then one row per file with its values and whether it is at or above the reference. Keep
the `--json` document when the numbers feed a comparison: `/verification:measure metrics` consumes
it when the `verification` plugin is installed (treat a report whose `status` is `empty` on either
side as INCONCLUSIVE); otherwise keep the JSON beside your notes and compare by hand.

## Reading the numbers

- The reference compares against `lines_non_blank`. The bundled default is 1000, the plugin's own
  number; it coincides with an informative figure in ISO/IEC 5055:2021 but that standard's
  normative form (§8.2.115) is a function-level percentage, so the file-level number is never
  cited as ISO-backed.
- A `null` value means the collector did not produce it (the bundled counter has no comment
  count); it is never zero.
- `status` is `complete` when every lane in scope was measured, `partial` when one was not, and
  `empty` when nothing was; the "Coverage of this run" table says why for every non-`ok` row.
- Exit 0 whenever a report was produced, including an `empty` one; exit 2 for a usage error such
  as an explicitly named path that does not exist; exit 3 when `scc` resolved but produced nothing
  parseable, with its stderr in the run table.

## Configuration

Everything tunable resolves through `.claude/code-metrics.yaml` (user-global, team, local
overlay; per-key override): the reference (`size.file_lines`), the mode (`size.mode`:
`file-lines` or `iso-8.2.115`, the latter comparing each function's non-empty lines against
`size.function_lines_pct` of the file's), scope exclusions, and per-lane collector order. The
report names the layer that supplied any value a personal layer changed. `/code-metrics:setup`
writes the team file and probes the collectors.

## What this skill does not do

- It does not run tests, edit files, or install `scc`; when `scc` is absent the run table says so
  and the bundled counter answers.
- It does not judge: no threshold here is a bar, and no `check` gate exists in this version.
- It does not measure complexity, duplication, coverage, or type debt; those are the sibling
  `audit-*` skills in this plugin, and `/code-metrics:principles` explains what each number can and
  cannot tell you.

## Gotchas

- Change scope needs a merge-base with the default branch; outside a git repository, or on a
  branch with no default-branch ancestor, pass paths or `--all` (the usage error says which).
- `--all` on a large tree counts every tracked and untracked-but-not-ignored file; the report
  caps the rendered table at 200 rows and says how many more are in the JSON.
- `scc` counts comment lines by language, so a language it does not know is counted as code;
  the bundled counter is comment-agnostic by construction and says so in every row's `labels`.
