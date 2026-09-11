# code-metrics: audit-size fix pass

## Brief

### TLDR

- The code-metrics dispatcher stops spending 34 of 35 seconds on per-file bash scaffolding: the binary sniff moves to one Python pass over the file list and lane detection lowercases extensions in bash itself.
- `audit-size` measures every text file in scope through a catch-all `other` lane that only the `file_lines` measure serves; every other measure reports `n/a` for it.
- `--all` is positioned as a first-class scope alongside the `change` default; the description stops disowning it.
- The Measures table sorts by the primary measure's value in its threshold direction, and the 200-row cap names what it kept.
- Report polish: the empty change scope says how to widen it, `Functions: 0` disappears from file-only summaries, and the 1000-line provenance sentence reads the same on every surface. Shipped as 0.1.9 with a changelog entry, one issue, one PR.

### Goal

A whole-tree `audit-size` run on this repository answers "which files are long" for the files that matter here (skill bodies, JSON fixtures, PowerShell) in about a second instead of 35, and the report a reader gets back is ordered by size, says how to widen an empty scope, and carries one consistent provenance story for its reference. The plugin keeps its measurement-only posture: no finding, no severity, no exit-code gate, nothing installed.

### Constraints

- ADR 0003: nothing emits a finding default-on without a measured sweep. This pass adds no gate and no verdict.
- The plugin installs nothing and runs external collectors only when they already resolve; `scc` stays optional.
- The `code-metrics/v1` document shape is a seam other tools read (`/verification:measure metrics`). Existing fields keep their meaning; the `other` lane is a new lane value, not a schema change.
- Every entry point stays Bash 4 plus Python 3.9 with no third-party dependency (the plugin's stated floor).
- Existing suites are the regression net: `audit-size.test.sh` (9), `dispatch.test.sh` (55), `detect-lanes.test.sh`, and the collector Python tests must stay green; new behaviour gets its own cases in the same suites.
- The skill description stays within the 1024-codepoint field maximum and keeps every single-quoted trigger phrase (the skill-quality check compares them against `origin/main`).
- `reference/config.md` and `scripts/config-defaults.json` are bound by a repository gate; any new lane key lands in both.

### Acceptance criteria

- `audit-size.sh --all` on this repository completes in under 5 seconds wall on this host (baseline 35.6s), and its `scope.files` count is unchanged.
- The same run reports `scope.unclassified` of 0 for text files: markdown, JSON, YAML, PowerShell, and SVG files appear as measured rows in lane `other`.
- `audit-complexity`, `audit-duplication`, and `audit-type-debt` run on a scope containing `other`-lane files still report `status: complete` when their own lanes are complete; the `other` row for each of their measures is `not-applicable` with a reason.
- `lanes.other.enabled: false` in `.claude/code-metrics.yaml` removes the lane, so a consumer can opt out.
- The Measures table lists rows in descending `lines_non_blank` order for `audit-size` (and ascending for a `below`-direction measure such as coverage), and a run over more than 200 rows prints a cap line naming the value key it sorted by.
- A change-scope run with no differing files prints a headline that names the base and says paths or `--all` widen the scope.
- A file-only report's summary line omits `Functions:`; a report with function rows still prints it.
- The `audit-size` description no longer contains the clause "for a repo-wide dashboard this is the wrong tool", its length stays under 1024 codepoints, and every trigger phrase present on `origin/main` is still present.
- The provenance string for `size.file_lines` is one sentence carried by `config-defaults.json`, and the SKILL.md body and `thresholds.md` cite it in the same words.
- IF a file in the `other` lane cannot be read, THEN its lane's `file_lines` run row is `unavailable` with the collector's reason and the run continues for every other lane.
- WHILE `scc` is absent, the `other` lane reports `line-counter` as its collector and each of its rows carries the `comment-agnostic` label, the same as every other lane.
- `plugin.json` reads 0.1.9 and `CHANGELOG.md` carries a `[0.1.9]` section describing each change above.
- One GitHub issue in `melodic-software/claude-code-plugins` carries the findings; the PR body opens with `Closes #<that issue>`.

### Captured assumptions

- The binary sniff moves to a Python helper invoked once over the scoped file list (the dispatcher already invokes Python per run for config and reporting), and lane detection's per-file `tr` subshell becomes `${ext,,}`; `detect-lanes.sh` otherwise keeps its shape and its suite. Revisit if the measured whole-tree time stays above 5 seconds after both changes.
- The `other` lane is assigned to every scoped, non-binary file that no other lane claims, including files with no extension. Revisit if a consumer reports generated or vendored text swamping the table; `scope.exclude` is the documented answer.
- The renderer's sort key is the first threshold's `value_key` in that threshold's direction; skills whose rows carry no such value (duplication clone groups) keep the current order. Revisit if a skill's primary value is not its first threshold.
- Version bump is 0.1.9 (the plugin has shipped features under 0.1.x before). Revisit if the maintainer treats a new lane as a minor bump.
- The issue is filed after the Brief is confirmed and before implementation, so the branch's commits can reference it.

### Out-of-scope

- Changing the 1000-line default reference or the 500 alternative.
- Any change to `iso-8.2.115` mode; it stays as shipped and still needs `lizard` or `radon`.
- Installing `scc` in the cloud bootstrap or anywhere else.
- A wholesale rewrite of scope resolution in Python.
- Per-language named lanes for markdown, PowerShell, or JSON.
- Any finding, severity, or `check` gate.

### Deferred questions

- None.

## Plan
