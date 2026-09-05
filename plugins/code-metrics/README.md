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
| `/code-metrics:audit-size` | Lines per file (total, blank, comment, code through `scc`; total and non-blank from a bundled counter otherwise) beside a cited reference; `size.mode: iso-8.2.115` adds the ISO function-percentage form. |
| `/code-metrics:setup` | `check` probes the interpreter, every configuration layer, and every collector; `apply` writes the tracked team configuration per key, idempotently, and never installs a tool. |

Further audit skills (`audit-complexity`, `audit-duplication`, `audit-coverage`,
`audit-type-debt`) and the `principles` literacy router land in the releases that follow; the
changelog is the record.

## Works in any repo

Lanes are detected from file extensions (TypeScript/JavaScript, Python, Bash, Go, and C#, whose
complexity lane is deferred and reported as such). When the consuming repository tracks
`.claude/ecosystems/<lane>.yaml` files, their `globs` override the bundled map for that lane. The
default scope is the change: files that differ from the merge-base with the default branch plus
uncommitted and untracked files; explicit paths or `--all` (every tracked or untracked-but-not-
ignored file) widen it. Nothing depends on a framework, a build system, or the publisher.

## Requirements

- **Bash and Python 3.9 or later** (`python3`, `python`, or `py -3`), plus `git` for change scope.
  Python is required for correctness: every entry point stops with a remediation message when it
  is absent.
- **Collectors, all optional.** A lane whose collector is absent reports `unavailable` with the
  install hint and the run continues; nothing is installed on your behalf.

| Collector | Used for | Install |
|---|---|---|
| `scc` | comment-aware line counts | `go install github.com/boyter/scc/v3@latest`, `brew install scc`, or a release binary |

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

Every skill description in a session shares one listing budget. The figures this plugin adds,
measured with `/skill-quality:check listing-budget` before and after the plugin was registered,
are recorded here when the plugin is registered in the marketplace.

## License

MIT (SPDX-License-Identifier: MIT).
