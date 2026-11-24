# Size

Lines per file is the one measure on the operator's list with a crisp definition and no
standard-backed file-level threshold. This action reports the number, per file in the scope,
beside a reference whose provenance is printed with it, and stops there: no pass or fail, no
severity, no finding. Deciding what to do with a long file is the reader's call; the report gives
them the number and the citation. The one exception is the opt-in check mode below, off unless a
repository's config turns it on.

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
"<skill-dir>/scripts/audit-size.sh" --file-lines 300     # count against the repository's own limit for this run
"<skill-dir>/scripts/audit-size.sh" --all --commits-since "1 year ago"   # add commits per file at or above the reference
"<skill-dir>/scripts/audit-size.sh" --check              # the opt-in check mode (below)
```

## Which reference

One reference, no stages: nothing here marks a second, higher length as "must refactor".

1. A code-metrics layer that sets `size.file_lines` is the repository's stated reference: run
   with no `--file-lines`.
2. Otherwise look for a file-length limit the repository already enforces: a rule in the
   configuration of whichever linter or analyzer it runs. Find it by reading that configuration;
   this plugin ships no list of tools or rule names. When one is set, pass it as
   `--file-lines <n>`, and tell the reader which file and rule it came from, and how that tool
   counts lines when it differs from non-blank lines. The report shows the layer as
   `this run (--file-lines)`. Offer `/code-metrics:setup apply size.file_lines=<n>` to make it the
   team reference.
3. With neither, the bundled default applies.

A limit a tool defines but the repository has not turned on is not the repository's limit.

Present the markdown report to the user as printed. It opens with the scope and a "Coverage of
this run" table (lane, collector, status, reason), then the reference with its provenance and
layer, then one row per file, longest first by `lines_non_blank`, with its values and whether it
is at or above the reference. Keep
the `--json` document when the numbers feed a comparison: `/verification:measure metrics` consumes
it when the `verification` plugin is enabled (treat a report whose `status` is `empty` on either
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

## Acting on a long file

A file at or above the reference is a candidate, not a task. Length alone is weak evidence: a long
file nobody edits costs nobody anything.

- **Act only when the file also changes often.** Run the script with `--commits-since <date>`
  (anything `git log --since` takes, such as `"1 year ago"`): it adds a table of the files at or
  above the reference with the commits that touched each since that date, automation authors left
  out, most-changed first. No count is a cutoff: the files high on both length and commits,
  against the others in the table, are the ones worth work. Report both numbers and the date.
  `/architecture:improve` (if enabled) reads the same history to find what to deepen.
- **File an issue; do not refactor in passing.** A long file met during other work gets a tracker
  item naming the file, its length, its commit count and the window: through
  `/work-items:track add` (if enabled), else the repository's own tracker. Never split it
  inside a change that is about something else.
- **To stop growth without fixing anything yet**, offer `/toolchain:ratchet` (if enabled) on the
  number of files at or above the reference (`summary.over_reference.file_lines` in the
  `--json --all` document).

## Check mode

`--check` applies the resolved `size.check` rule to the change and sets the exit code, for a
pre-commit hook or CI step the repository wires itself. The rule counts the report's unit,
non-blank lines against `size.file_lines`, with `scope.exclude` applied:

| `size.check` | Fails |
|---|---|
| `report` (default) | nothing: exit 0 whatever the sizes |
| `crossing` | a changed file below the reference at the base and at or above it now |
| `crossing-or-growth` | a crossing, and a file already at or above the reference that grew |

A file already over the reference and not grown never fails. Under `crossing`, one that grew is
listed as reported and passes, as the review plugin's size-crossing note treats it;
`crossing-or-growth` is for a repository that wants long files held where they are. Both counts
use the bundled counter's non-blank rule, whichever collector filled the report, so an unchanged
file never reads as grown; the base count follows a rename, a file new since the base counts 0
there, and each copy a sanctioned-replication row stands for is checked on its own. A file a
`scope.registries` cluster line (`<canonical> -> <member>...`) names as a member is a copy measured
at its canonical: it is listed with the canonical's path and never fails, and the canonical keeps
the rule.

The report gains a "Size check" section (the `size_check` block under `--json`): each listed file
with its base and head counts, then a `PASS` or `FAIL` line. A `FAIL` line says what to do: split
the file along a real responsibility boundary; never delete code or squash lines to get under the
number; where no such boundary exists, raise `size.file_lines` or add the file to `scope.exclude`,
with a comment giving the reason, in the team file.

- CI: `audit-size.sh --check` measures the merge-base diff, like the default run.
- Pre-commit: `audit-size.sh --check --base HEAD` measures the uncommitted change. Pass it no file
  names (pre-commit's `pass_filenames: false`): explicit paths, like `--all`, have no base.

Exit 0 when nothing fails, 1 when a file fails, 2 when the check cannot decide: no change scope,
an invalid `size.check`, a null `size.file_lines`, an unreadable file, a lane whose `file_lines`
was not measured, or a collector that failed (under `report`, a failed collector keeps exit 3). A crossing this change causes is this change's to fix, so splitting the file
here is in scope, unlike the long file met in passing under "Acting on a long file".

## Configuration

Everything tunable resolves through the code-metrics layers (team
`docs/conventions/code-metrics.yaml`, personal override `docs/conventions/code-metrics.local.yaml`; per-key override; keys in `<plugin-root>/reference/config.md`): the reference
(`size.file_lines`), the check rule (`size.check`, above), the mode (`size.mode`: `file-lines`, or `iso-8.2.115`, which adds a
`function_lines` measure comparing each function's non-empty lines against
`size.function_lines_pct` of the file's, from a collector that reports function ranges such as
`lizard` or `radon`; Bash has none and its row says so), scope exclusions (`scope.exclude`), and
per-lane collector order. `--file-lines <n>` replaces the reference for one run and writes no
layer. The report names the layer that supplied any value a personal layer
changed. `/code-metrics:setup` writes the team file and probes the collectors.

## What this action does not do

- It does not run tests, edit files, or install `scc`; when `scc` is absent the run table says so
  and the bundled counter answers.
- It does not judge: no threshold here is a bar, outside the opt-in check mode.
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
