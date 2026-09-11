---
description: "Measure duplicated code as clone classes over the changed files, a path, or the whole tree: each class's duplicated lines and tokens with every instance's file and line range, rolled up per lane (TypeScript/JavaScript, Python, Bash, Go, C#) and per directory, from whichever clone detector already resolves. Replication the target repository declares about itself in a sanctioned-replication registry (a path-within-plugin or a canonical-to-copies cluster line) is subtracted from the total and reported as an exclusion naming the registry line rather than as debt; the report emits no finding, no severity, and no exit-code gate. Use when: 'is this duplicated', 'find copy-paste code', 'clone detection', 'duplication report', 'how much of this change is copied', 'DRY check', 'redundant code', 'duplicated lines in the diff'; for lines per file use /code-metrics:audit-size, and for what a duplication number can and cannot support use /code-metrics:principles."
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
table (lane, collector, status, reason), then one row per clone group, largest first, listing
every instance as `file:start-end`, then a rollup per lane and per directory, then the summary
lines: files with clones, the duplicated-line total, how many groups a registry excluded, and
which lanes were partial. When the report opens with `No clone detector ran in any lane`, offer
the user the install command that headline carries (`npm install -g jscpd`, or a devDependency)
and run it only when they confirm; never install silently and never `npx`-fetch it. Keep the
`--json` document when the numbers feed a comparison:
`/verification:measure metrics` consumes it when the `verification` plugin is installed (treat a
report whose `status` is `empty` on either side as INCONCLUSIVE); otherwise keep the JSON beside
your notes and compare by hand.

## Reading the numbers

- A clone group is reported beside no reference. There is no configured bar for duplication in
  this plugin and no standard sets one, so nothing is ever counted as `over_reference`.
- A group is a clone class, not a detector pair. `jscpd` and PMD CPD report clones as pairs, so
  seventeen identical copies arrive as sixteen two-instance rows; this skill merges rows that
  share an instance with an identical file and line range into one row per class before it
  counts anything. Copies that share only part of a fragment are named with different ranges and
  stay separate groups: the merge joins on identity, never on overlap, so a class is never wider
  than what the detector called identical.
- `summary.duplicated_lines` counts each class once, using the length of the class, not the sum
  over its instances: three copies of a 41-line block are 41 duplicated lines, not 82 or 123. The
  count is what survived the registries.
- `summary.by_lane` and `summary.by_directory` roll the surviving classes up: each maps to
  `{groups, duplicated_lines}`, the directory map for `.` and every ancestor of each class's first
  instance. A class counts once under every ancestor, so a parent includes its children and the
  directory rows cannot be summed; `by_directory["."]` and the per-lane sum both restate the
  totals. The markdown lists directories to `duplication.rollup_depth`; the JSON carries all.
- A file larger than `duplication.max_size` (or longer than `duplication.max_lines`, when set) is
  left out of the scan and never silently dropped: the lane's run row is `partial` with how many
  files were skipped and the largest one, the document is `partial`, and the summary carries a
  `Partial:` line naming the lane.
- The registry is an **exclusion**, not a suppression: it is derived from the target repository's
  own declaration that those copies are deliberate, so no suppression record is involved and the
  excluded groups stay in the document under `excluded[]` with the registry path, the 1-based line
  number, and the line's text. A group is excluded only when one registry line accounts for every
  instance and each instance sits under a different carrying directory; two copies inside one
  directory are ordinary duplication and stay.
- A value the detector did not produce is `null`, never `0`: `dupl` reports no token count, so
  its rows carry `tokens: null`.
- `status` is `complete` when every lane in scope was measured, `partial` when one was not or
  when a cap left files out of one, and `empty` when nothing was; a run that measured nothing
  prints "Measured nothing" and states no duplication figure at all, which is not the same as zero
  duplication. A lane that skipped every file is still `partial`: its row says what was skipped.
- Exit 0 whenever a report was produced, including an `empty` one; exit 2 for a usage error such
  as a named registry or scope path that does not exist; exit 3 when a detector resolved but
  produced nothing parseable, with its stderr in the run table. A detector's own non-zero exit is
  not a failure when it produced a report, which is how `jscpd` and PMD CPD signal "clones found".

## Configuration

Everything tunable resolves through `.claude/code-metrics.yaml` (user-global, team, local
overlay; per-key override; keys in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`):
`duplication.min_tokens` (default 50), `duplication.min_lines` (default 5),
`duplication.ignore` (globs handed to the detector's own ignore option), `duplication.max_size`
(default `1mb`, binary units; a larger file is left out of the scan and reported), `duplication.max_lines`
(default `null`, no line cap), `duplication.rollup_depth` (default 2, how deep the markdown
per-directory rollup lists), and `scope.registries` (sanctioned-replication registries, each path
relative to the repository root, each also nameable on the command line with `--registry`, and
read by every audit in this plugin; `duplication.registries` is the older name and still resolves
when the scope-level list is empty). A cap of `null` or `0` means no cap. `/code-metrics:setup`
writes the team file and probes the collectors.

A registry line has one of two shapes. A plain line is one path-within-plugin, taken whole with
any spaces: a class is excluded when every instance ends with that path and the copies sit in
distinct carrying directories. A cluster line, `<canonical> -> <member>...`, names a root-relative
canonical copy and the plugin paths or gitignore-style globs that carry it
(`lib/hook-utils.sh -> plugins/*/hooks/hook-utils.sh`): a class is excluded when every instance is
the canonical or matches a member and the instances' directories are pairwise distinct. Instance
paths are compared root-relative, so a run from a subdirectory matches the same lines, and the
first matching line in file order wins.

This script exports the five tunables to the collector adapters as
`CODE_METRICS_DUP_MIN_TOKENS`, `CODE_METRICS_DUP_MIN_LINES`, `CODE_METRICS_DUP_IGNORE`,
`CODE_METRICS_DUP_MAX_LINES`, and `CODE_METRICS_DUP_MAX_SIZE`, which is the only channel an
adapter reads them through. `jscpd` passes the first three to the tool and applies the two caps
itself before the tool runs, because jscpd 4 and 5 disagree on what their own `--max-size` and
`--max-lines` default to and neither names a file it skipped; `dupl` and `cpd` have no
minimum-lines, ignore-glob, or cap option, so their adapters apply the minimum after parsing,
report the ignore globs as unused, and scan every file in scope.

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

## Next

- The numbers feed a before-and-after comparison: `/verification:measure metrics`.
- A surviving clone is about to be called debt: `/code-metrics:principles`.

## Gotchas

- Change scope needs a merge-base with the default branch; outside a git repository, or on a
  branch with no default-branch ancestor, pass paths or `--all` (the usage error says which).
- A registry named on the command line or in `scope.registries` that does not exist is a
  usage error, not a silent no-op: a stale registry path would otherwise turn every exclusion off
  without saying so.
- Clone detection compares the files in scope with each other. A default-scope run sees only the
  changed files, so a block copied from a file the change did not touch is not found; use `--all`
  or name both paths when that is the question.
- The pair merge is exact only for byte-identical copies. A class whose copies drifted by a line
  is reported as the detector saw it: the identical span as one class, and the drifted copy's
  shorter overlap as a second group naming the same file with a different range.
- jscpd 4 and jscpd 5 tokenize differently, so the same tree yields different class counts under
  the two majors; compare runs made with one detector version, never across the boundary.
- Lowering `duplication.min_tokens` finds more and smaller clones, most of them boilerplate the
  language forces; the defaults are the detector's own conservative pair.
