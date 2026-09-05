# code-metrics

A Claude Code plugin that measures the shape of a change and cites where every number comes
from. Lines per file, cyclomatic and cognitive complexity, Halstead difficulty, duplication,
coverage per function with CRAP, and type debt, each as a read-only audit that reads source
files and existing build artifacts, runs an external collector only when one already resolves,
and prints a report whose references carry their provenance. It never runs tests, never edits
code, never installs a tool, and never renders a keep-or-retire verdict: a reference here is a
value to count against, not a bar.

## The skills

| Skill | What it does |
|---|---|
| `/code-metrics:audit-complexity` | Per-function cyclomatic and cognitive complexity and Halstead difficulty from whichever collector resolves (`lizard`, `radon`, ESLint rules, `gocyclo`, `gocognit`, `shellmetrics`, `multimetric`), beside the ISO/IEC 5055 §8.2.117 reference of 20 with 10 and 15 selectable; cognitive and Halstead carry no standard threshold. |
| `/code-metrics:audit-size` | Lines per file (total, blank, comment, code through `scc`; total and non-blank from a bundled counter otherwise) beside a cited reference; `size.mode: iso-8.2.115` adds the ISO function-percentage form. |
| `/code-metrics:audit-duplication` | Clone groups (duplicated lines and tokens, every instance's range) from `jscpd`, `dupl`, or PMD CPD, minus the replication the repository declares in a sanctioned-replication registry, which is an exclusion, not a suppression. |
| `/code-metrics:audit-coverage` | Line coverage per file and per function read from the artifacts a build already produced (lcov 1.x and 2.2, Cobertura, coverage.py JSON, Go cover profile), plus CRAP per function from the complexity rows; it never runs a test, a missing artifact is a visible warning, and a function with no executable lines reports `null`, never zero. |
| `/code-metrics:audit-type-debt` | The typed-code percentage per lane: `type-coverage` for TypeScript, mypy's `--any-exprs-report` for Python; no standard or CWE anchors the measure, so the reference is `null` by design. C# is reported as not applicable. |
| `/code-metrics:principles` | Metric literacy: what each measure can and cannot tell you, where every reference value came from, CRAP's corrected provenance, the cross-metric caveats (carried once, here), and gated pointers to the plugins that own mutation score, tautological tests, dead code, coupling, and lint. |
| `/code-metrics:setup` | `check` probes the interpreter, every configuration layer, and every collector; `apply` writes the tracked team configuration per key, idempotently, and never installs a tool. |

## Works in any repo

Lanes are detected from file extensions (TypeScript/JavaScript, Python, Bash, Go, and C#, whose
complexity lane is deferred and reported as such). When the consuming repository tracks
`.claude/ecosystems/<lane>.yaml` files, their `globs` override the bundled map for that lane. The
default scope is the change: files that differ from the merge-base with the default branch plus
uncommitted and untracked files; explicit paths or `--all` (every tracked or untracked-but-not-
ignored file) widen it. Nothing depends on a framework, a build system, or the publisher.

## Requirements

- **Bash 4 or later and Python 3.9 or later** (`python3`, `python`, or `py -3`), plus `git` for
  change scope. macOS ships bash 3.2, so install a current bash (`brew install bash`); Windows
  needs Git Bash. Every entry point checks the bash version and stops with that remediation.
  Python is required for correctness: every entry point stops with a remediation message when it
  is absent.
- **Collectors, all optional.** A lane whose collector is absent reports `unavailable` with the
  install hint and the run continues; nothing is installed on your behalf.

| Collector | Used for | Install |
|---|---|---|
| `scc` | comment-aware line counts, every lane | `go install github.com/boyter/scc/v3@latest`, `brew install scc`, or a release binary |
| `lizard` | cyclomatic complexity and function ranges for TypeScript/JavaScript, Python, Go | `pip install lizard` or `pipx install lizard` |
| `radon` | Python cyclomatic complexity, Halstead, function ranges | `pip install radon` |
| `eslint` with the core `complexity` rule | TypeScript/JavaScript cyclomatic complexity when ESLint is wired | `npm install --save-dev eslint` |
| `eslint-plugin-sonarjs` | TypeScript/JavaScript cognitive complexity | `npm install --save-dev eslint eslint-plugin-sonarjs` |
| `gocyclo`, `gocognit` | Go cyclomatic and cognitive complexity | `go install github.com/fzipp/gocyclo/cmd/gocyclo@latest`, `go install github.com/uudashr/gocognit/cmd/gocognit@latest` |
| `shellmetrics` | Bash cyclomatic complexity | one POSIX shell script from github.com/shellspec/shellmetrics, placed on `PATH` |
| `multimetric` | Halstead difficulty in every lane; Bash cyclomatic as a labelled approximation | `pip install multimetric` |
| `jscpd` | duplication in every lane | `npm install -g jscpd`, or a devDependency |
| `dupl` | Go duplication | `go install github.com/mibk/dupl@latest` |
| PMD CPD | duplication for the non-shell lanes when `jscpd` is absent | the PMD 7 distribution or `brew install pmd` (needs a JVM) |
| `type-coverage` | TypeScript type coverage; needs a resolvable `typescript` in the project | `npm install --save-dev type-coverage typescript` |
| `mypy` | Python `Any`-expression report | `pip install mypy`, `pipx install mypy`, or `uv tool install mypy` |

Python has no maintained cognitive-complexity collector and Bash has none for cognitive
complexity or function ranges; those rows report `unavailable` with the validation date, and the
run continues.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install code-metrics@melodic-software
```

## Configuration

This plugin has no `userConfig`. Everything tunable lives in the consumer's
`.claude/code-metrics.yaml`, layered as user-global (`~/.claude/code-metrics.yaml`), team
(tracked), and local overlay (`.claude/code-metrics.local.yaml`, gitignored; recommended line
`.claude/**/*.local.*`) with per-key override, and every key has a bundled default
(`scripts/config-defaults.json`), so the plugin works with no configuration at all. The consumer's
`.claude/ecosystems/<lane>.yaml` files, when tracked, override lane detection with their `globs`
and `enabled`. References ship with their provenance: cyclomatic 20 cites ISO/IEC 5055:2021
§8.2.117; the 1000-line file default is the plugin's own number and says so. Files are written in
a documented YAML subset (block style, flow sequences of scalars, no flow mappings). Every key:
`reference/config.md`; `/code-metrics:setup` writes the team layer and probes the collectors.

## The report

Every audit prints one `code-metrics/v1` JSON document (`--json`) or its markdown rendering. The
document opens with a "Coverage of this run" table naming, per lane and measure, the collector
used or the reason none did, and a `status` of `complete`, `partial`, or `empty`, so a run that
measured nothing can never read as green. Field reference: `reference/report-schema.md`. Tool
provenance stamps: `reference/collectors.md`.

## Listing budget

Every skill description in a session shares one listing budget, and Claude Code drops the
least-invoked descriptions first when it overflows. Measured with
`plugins/skill-quality/scripts/check-listing-budget.sh` over every marketplace plugin's skills on
2026-09-05, this plugin adds six listing-eligible descriptions (`setup` is model-hidden and costs
nothing) at these estimated sizes:

| Measurement | Characters |
|---|---|
| Marketplace aggregate before this plugin | 135,541 |
| Marketplace aggregate with this plugin | 141,411 |
| This plugin alone | 5,870 |

The aggregate is an upper-bound estimate against the documented 8,000-character fallback; a
consumer who installs only this plugin sits well inside it, and `/doctor` reports the resolved
figure for a live session.

## Known gaps

- The two convention adopter rows (the marketplace's per-plugin conventions registry) are deferred
  until the operator settles which conventions this plugin adopts; the plugin's own conventions
  are the ones its reference files declare.
- Bash has no collector for cognitive complexity or function ranges, and Python none for cognitive
  complexity; those rows report `unavailable` with the validation date rather than a number.
- C# is counted and its duplication measured, but its complexity lane is deferred to a native
  collector and its type debt is reported as not applicable.

## License

MIT (SPDX-License-Identifier: MIT).
