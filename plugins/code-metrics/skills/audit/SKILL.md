---
description: "Measure code for the changed files (the default), explicit paths, or the whole tree (`--all`), each number beside a configurable reference with its provenance. Reports, never gates. Actions: size (lines per file, every text file), complexity (per-function cyclomatic, cognitive and Halstead from collectors already installed), type-debt (typed-code percentage from type-coverage and mypy). Use when: 'how long are these files', 'lines per file', 'which files are too big', 'is this file over 1000 lines', 'how complex is this code', 'cyclomatic complexity', 'cognitive complexity', 'Halstead difficulty', 'how much of this is typed', 'type coverage', 'how many anys are in this', 'type debt'. Coverage and CRAP: /code-metrics:audit-coverage."
argument-hint: "<size|complexity|type-debt> [--json] [--all] [--base <ref>] [<path>...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/audit-size.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/audit-complexity.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/audit-type-debt.sh:*)", "Bash(git branch --show-current:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Lines, complexity and typed-code numbers beside cited references, no verdict
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Variables

Arguments: `$ARGUMENTS`

The first word names the action; the rest passes to its script unchanged.

## Actions

| Argument | Measures | Script | Full process |
|---|---|---|---|
| `size` | Lines per file, every text file in every lane | `${CLAUDE_SKILL_DIR}/scripts/audit-size.sh` | `actions/size.md` |
| `complexity` | Per-function cyclomatic and cognitive complexity and Halstead difficulty | `${CLAUDE_SKILL_DIR}/scripts/audit-complexity.sh` | `actions/complexity.md` |
| `type-debt` | Typed-code percentage per file and per lane (TypeScript, Python) | `${CLAUDE_SKILL_DIR}/scripts/audit-type-debt.sh` | `actions/type-debt.md` |

With no action word, take the action from the request: file length or lines is `size`,
complexity is `complexity`, typing or `any` is `type-debt`. When the request names none of them,
list the three actions and ask which to run. Read the action's file before running its script; one
action per invocation.

## Standing rules

- Every action reports and never gates: each number sits beside a reference with its provenance,
  and nothing here is a pass, a fail, a finding or a severity.
- Run the action's bundled script; never count, estimate or grep the measure by hand.
- Scope is the change by default (the merge-base diff plus uncommitted files); explicit paths or
  `--all` widen it, and `--json` prints the `code-metrics/v2` document instead of markdown.
- Present the markdown report as printed. Keep the `--json` document when the numbers feed a
  comparison: `/verification:measure metrics` consumes it when the `verification` plugin is
  installed (treat `status: empty` on either side as INCONCLUSIVE); otherwise keep it beside your
  notes and compare by hand.
- A `null` value is a number the collector did not produce, never zero.
- Nothing is installed; a missing collector is a row in the run table with its install hint.

## Spoke paths

The `actions/` files write this skill's directory as `<skill-dir>`, which is `${CLAUDE_SKILL_DIR}`,
and the plugin's root directory as `<plugin-root>`, which is `${CLAUDE_PLUGIN_ROOT}`. Put those
paths in place of the placeholders before running a command: a `${…}` token in a supporting file
is not one this plugin can rely on being expanded, either in the file or in the Bash tool. Where
each plugin variable resolves, and where it is exported: the plugins reference,
<https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>.

## What this skill does not do

- It does not run tests, edit files, or install a collector.
- It does not judge: no reference is a bar, and no `check` gate exists in this version.
- It does not measure duplication, coverage or suppressions; those are the sibling `audit-*`
  skills in this plugin, and `/code-metrics:principles` explains what each number can and cannot
  tell you.

## Next

- The numbers feed a before-and-after comparison: `/verification:measure metrics`.
- A complex function's coverage and CRAP score are the real question:
  `/code-metrics:audit-coverage`.
- A number is about to be quoted or read as a bar: `/code-metrics:principles`.

## Gotchas

- Change scope needs a merge-base with the default branch; outside a git repository, or on a
  branch with no default-branch ancestor, pass paths or `--all` (the usage error says which).
- The report `skill` field and the dispatcher id stay `audit-size`, `audit-complexity` and
  `audit-type-debt`: they name the producer, so reports taken before and after the move still
  compare.
- Each action's own gotchas are in its file under `actions/`.
