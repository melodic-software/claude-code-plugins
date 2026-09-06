---
description: "Measure duplicated code as clone groups over the changed files, a path, or the whole tree: each group's duplicated lines and tokens with every instance's file and line range, per lane (TypeScript/JavaScript, Python, Bash, Go, C#) from whichever clone detector already resolves. Replication the target repository declares about itself, a file vendored into several plugins and listed by path-within-plugin in a sanctioned-replication registry, is subtracted from the total and reported as an exclusion naming the registry line rather than as debt, and the report emits no finding, no severity, and no exit-code gate. Use when: 'is this duplicated', 'find copy-paste code', 'clone detection', 'duplication report', 'how much of this change is copied', 'DRY check', 'redundant code', 'duplicated lines in the diff'; for lines per file use /code-metrics:audit-size, and for what a duplication number can and cannot support use /code-metrics:principles."
argument-hint: "[--json] [--all] [--base <ref>] [--registry <file>] [<path>...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/audit-duplication.sh:*)", "Bash(git branch --show-current:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Clone groups minus the replication the repo declares, no verdict
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Duplication is the measure most likely to report noise, because some replication is deliberate:
a repository that vendors one helper into seventeen plugins on purpose has seventeen copies and
zero debt. This skill reports the clone groups a detector found, then subtracts the groups the
target repository has already declared about itself, and stops there: no pass or fail, no
severity, no finding. What to do about a surviving clone is the reader's call.

Collectors, tried in ladder order per lane:

| Collector | Lanes | Values per clone group | When |
|---|---|---|---|
| `jscpd` | every lane | `lines`, `tokens` | `jscpd` resolves on `PATH` or in `./node_modules/.bin` |
| `dupl` | Go only | `lines`, `tokens` null | `jscpd` did not resolve and `dupl` did |
| `cpd` (PMD) | TypeScript/JavaScript, Python, Go, C# | `lines`, `tokens` | `jscpd` did not resolve and `pmd` did (never for Bash: CPD has no shell language) |

No collector resolves means the lane's row says so with the tool's install hint and the run
continues. This plugin never installs, downloads, or `npx`-fetches a detector.

## Run it

```bash
"${CLAUDE_SKILL_DIR}/scripts/audit-duplication.sh"                       # the change: diff from the merge-base plus uncommitted files
"${CLAUDE_SKILL_DIR}/scripts/audit-duplication.sh" src/ lib/            # explicit paths (a missing one is a usage error)
"${CLAUDE_SKILL_DIR}/scripts/audit-duplication.sh" --all                # every tracked or untracked-but-not-ignored file
"${CLAUDE_SKILL_DIR}/scripts/audit-duplication.sh" --registry scripts/cross-plugin-source-registry.txt --all
"${CLAUDE_SKILL_DIR}/scripts/audit-duplication.sh" --json --all src/    # the code-metrics/v1 document instead of markdown
```

Present the markdown report as printed. It opens with the scope and a "Coverage of this run"
table (lane, collector, status, reason), then one row per clone group listing every instance as
`file:start-end`, then the summary line with the duplicated-line total and how many groups a
registry excluded. Keep the `--json` document when the numbers feed a comparison:
`/verification:measure metrics` consumes it when the `verification` plugin is installed (treat a
report whose `status` is `empty` on either side as INCONCLUSIVE); otherwise keep the JSON beside
your notes and compare by hand.

## Reading the numbers

- A clone group is reported beside no reference. There is no configured bar for duplication in
  this plugin and no standard sets one, so nothing is ever counted as `over_reference`.
- `summary.duplicated_lines` counts each group once, using the length of the group, not the sum
  over its instances: two copies of a 41-line block are 41 duplicated lines, not 82. The count is
  what survived the registries.
- The registry is an **exclusion**, not a suppression: it is derived from the target repository's
  own declaration that those copies are deliberate, so no suppression record is involved and the
  excluded groups stay in the document under `excluded[]` with the registry path, the 1-based line
  number, and the line's text. A group is excluded only when one registry line accounts for every
  instance and each instance sits under a different carrying directory; two copies inside one
  directory are ordinary duplication and stay.
- A value the detector did not produce is `null`, never `0`: `dupl` reports no token count, so
  its rows carry `tokens: null`.
- `status` is `complete` when every lane in scope was measured, `partial` when one was not, and
  `empty` when nothing was; a run that measured nothing prints "Measured nothing" and states no
  duplication figure at all, which is not the same as zero duplication.
- Exit 0 whenever a report was produced, including an `empty` one; exit 2 for a usage error such
  as a named registry or scope path that does not exist; exit 3 when a detector resolved but
  produced nothing parseable, with its stderr in the run table. A detector's own non-zero exit is
  not a failure when it produced a report, which is how `jscpd` and PMD CPD signal "clones found".

## Configuration

Everything tunable resolves through `.claude/code-metrics.yaml` (user-global, team, local
overlay; per-key override; keys in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`):
`duplication.min_tokens` (default 50), `duplication.min_lines` (default 5),
`duplication.ignore` (globs handed to the detector's own ignore option), and
`duplication.registries` (sanctioned-replication registries, each path relative to the repository
root, and each also nameable on the command line with `--registry`). `/code-metrics:setup` writes
the team file and probes the collectors.

This script exports the three tunables to the collector adapters as
`CODE_METRICS_DUP_MIN_TOKENS`, `CODE_METRICS_DUP_MIN_LINES`, and `CODE_METRICS_DUP_IGNORE`, which
is the only channel an adapter reads them through. `jscpd` passes all three to the tool;
`dupl` and `cpd` have no minimum-lines or ignore-glob option, so their adapters apply the
minimum after parsing and report the ignore globs as unused.

`cpd` (PMD) sits after `jscpd` on `${CLAUDE_PLUGIN_ROOT}/scripts/collector-ladder.tsv` for every
lane but Bash, so it runs only when `jscpd` does not resolve and `pmd` does. A repository that
already runs PMD puts it first with `lanes.<lane>.collectors.duplication: [cpd, jscpd]`; collector
overrides are validated against the ladder file and an unknown name is dropped with a warning.

## What this skill does not do

- It does not run tests, edit files, remove a clone, or install a detector; when none resolves the
  run table says so and prints the install hint.
- It does not judge. No duplication figure here is a bar, and no `check` gate exists in this
  version.
- It does not find cross-language clones. Every detector here is token-based within one language
  (`jscpd` groups JavaScript with TypeScript and nothing wider), so a C# method reimplemented in
  Python is invisible to it.
- It does not measure size, complexity, coverage, or type debt; those are the sibling `audit-*`
  skills in this plugin, and `/code-metrics:principles` explains what each number can and cannot
  tell you.

## Gotchas

- Change scope needs a merge-base with the default branch; outside a git repository, or on a
  branch with no default-branch ancestor, pass paths or `--all` (the usage error says which).
- A registry named on the command line or in `duplication.registries` that does not exist is a
  usage error, not a silent no-op: a stale registry path would otherwise turn every exclusion off
  without saying so.
- Clone detection compares the files in scope with each other. A default-scope run sees only the
  changed files, so a block copied from a file the change did not touch is not found; use `--all`
  or name both paths when that is the question.
- `jscpd` reports pairs, so seventeen identical copies arrive as sixteen two-instance groups
  rather than one seventeen-instance group; the registry excludes each of them on the same line.
- Lowering `duplication.min_tokens` finds more and smaller clones, most of them boilerplate the
  language forces; the defaults are the detector's own conservative pair.
