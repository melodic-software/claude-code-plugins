---
description: "Deterministic pass/fail gate over a repository's path-scoped instruction surfaces. Verifies every `.claude/rules/` glob actually resolves (matches at least one tracked file, valid bracket expressions, inside the documented 1,000-pattern / 4 MiB brace-expansion budget) and that the always-loaded rules index is in sync with the rules on disk. Every one of these failures is SILENT in Claude Code: a zero-match glob is a rule that never fires, an unbalanced `[` matches nothing, and an over-budget pattern is used unexpanded so its braces match no file. Use when: 'check my rules', 'are my path-scoped rules actually firing', 'is the rules index stale', 'validate paths frontmatter', 'why is my rule not loading', 'CI gate for .claude/rules', or after any change to a rule's `paths:` or to the rules tree. Read-only. Reports and exits non-zero, never edits; the sibling realign skill applies fixes."
argument-hint: "[--file <index-path>] [--breadth-max <pct>]. Default: gate the whole repository"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  [
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/verify-load.sh:*)",
    "Read",
    "Grep",
    "Glob",
  ]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Gate that every path-scoped rule glob resolves and the rules index is current
---

## Pre-computed context

!`"${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh" check 2>/dev/null || echo "- Orientation unavailable"`

## Purpose

A gate, not an audit. It answers one question with one exit code: **would every path-scoped
instruction surface in this repository actually load when it is supposed to, and does the
always-loaded index still describe what is on disk?**

It exists because every failure mode here is silent. Claude Code does not warn when a rule's glob
matches nothing, when a bracket expression is malformed, or when a pattern exceeded the brace budget
and was used unexpanded. The rule simply never fires, and the convention it carries is quietly
absent from every session that needed it. A repository can accumulate a dozen dead rules and look
perfectly healthy.

Wire it into CI beside the linters. It is fast, deterministic, and has no judgment layer to drift.

## What it checks

| Check | Mechanism | Failure means |
|---|---|---|
| Glob resolves | `glob-tools.sh rules` | The rule never fires for any file in the repository |
| Bracket expressions valid | same | The pattern silently matches nothing |
| Brace budget respected | same | The pattern is used unexpanded; its braces match nothing |
| Glob not over-broad | same | Advisory. The rule loads so often it saves nothing |
| Index in sync | `render-index.sh check` | Deferred surfaces are unreachable from subagents |
| Index target loaded at all | `render-index.sh reachable` | The index exists and Claude Code never reads it |

The last one is the newest and the least obvious. Claude Code reads `CLAUDE.md`, not `AGENTS.md`. A
repository carrying both with no import between them gets a perfectly-generated, perfectly-in-sync
index that never enters context, the entire subagent-gap mitigation doing nothing while every other
check reports green. Sync and reachability are independent questions; ask both.

Over-broad is the one **warning** rather than a failure: breadth is a judgment about whether a
demotion was worth making, not a statement that the rule is broken. Everything else is a hard fail.

## Running it

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh" rules
"${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh" check --file <index-file>
"${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh" reachable --file <index-file>
```

`<index-file>` is a precedence order, not a procedure. Take the first that exists:

| Precedence | Target | Why |
|---|---|---|
| 1 | An explicit `--file` argument | The operator's own choice wins |
| 2 | Root `AGENTS.md` | The portable home. Other agents read it too |
| 3 | Root `CLAUDE.md` | The Claude-only fallback |

Name the winner in the report; the run is not complete until the output states which file was
checked. If none exists, say so and skip the index check rather than inventing a target. The glob
checks still decide the verdict.

**A repository with no index block yet is not a failure.** `render-index.sh check` exits 3 for that
case, and 3 means "nothing to compare", not "broken". Report it as a recommendation. The index is
what makes deferred rules reachable from subagents. Leave the gate's verdict to the glob
checks. Only a repository that *has* an index and has let it drift fails on that check.

### Escalating to empirical verification

Every check above is static. It reads files and reasons about what Claude Code *would* do. When the
operator asks why a rule is not firing despite a green gate, or wants proof rather than inference,
escalate:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-load.sh" --trigger <covered file> --expect <the rule>
```

That drives the real CLI with an `InstructionsLoaded` hook and reports what actually loaded, with
the reason for each load. It costs a model call, so it is an escalation rather than part of the
default gate. `VERDICT UNKNOWN` means the probe could not run. Report it as unmeasured, never as a
pass.

Pass `--breadth-max` through when the operator supplies it. The default of 75% is a starting point,
not a law; a documentation repository where `**/*.md` legitimately covers most files should raise
it rather than live with a standing warning.

## Reading the output

Both scripts emit deterministic TSV. `glob-tools.sh` rows are:

```text
PATTERN <tab> source-rule <tab> pattern <tab> expanded <tab> matches <tab> status
SUMMARY <tab> tracked <tab> patterns <tab> invalid <tab> overbroad <tab> verdict
```

Report per failing pattern: the rule file, the pattern, the status, and **what the operator should
do about it**. The three failure statuses have different fixes and saying "invalid" helps nobody.

| Status | What actually happened | Fix |
|---|---|---|
| `zero-match` | No tracked file matches | The glob is wrong, or the code it described was moved or deleted. Correct the pattern, or retire the rule |
| `bad-bracket` | A `[` cannot be read as a bracket expression | Escape it as `\[` if it is a literal, or close the expression |
| `over-budget` | Expansion exceeded 1,000 patterns or 4 MiB | Split the rule, or replace brace groups with a broader pattern |
| `over-broad` | Matches most of the repository | Advisory. Narrow it, or accept it and raise `--breadth-max` |

## Hard rules

- **Read-only.** No `Edit`, no `Write`, no mutating `Bash`. Fixing a broken glob is the sibling
  `realign` skill's job, or the operator's.
- **Never fabricate a verdict.** If a script cannot run, because this is not a git repository or
  tooling is missing, report that plainly and exit non-zero. A gate that passes because it could
  not measure is worse than no gate.
- **Never consult the findings artifact.** This skill verifies the repository's actual state. An
  audit artifact is a snapshot of a past run, and a gate that trusted one could report health for a
  repository that has since broken.
- **Exit code is the product.** 0 clean, non-zero otherwise, whatever the prose around it says.

## Gotchas

- **Exit 3 is not a failure.** `render-index.sh check` returns 3 when the file carries no index
  block at all. Treating that as drift fails every repository that has not adopted the index yet,
  which is most of them on first run.
- **A begin marker with no end marker returns 3, not 1.** The tools refuse to guess a block's
  extent rather than overwrite an unknown span. Read it as "malformed, needs a human", not as
  "absent".
- **`over-broad` never moves the verdict.** It shares an output column with the three real
  failures and is the one that does not fail the gate. Reporting it as a failure trains operators
  to ignore the gate.
- **A zero-match glob usually means stale content, not a typo.** The reflex is to fix the pattern.
  Check whether the code it described still exists first. A rule for a deleted subsystem should be
  retired, not re-globbed.
- **Passing because nothing could be measured is the worst outcome.** Outside a git repository, or
  with tooling missing, the scripts cannot answer. Exit non-zero and say why; a green gate that
  measured nothing is a false assurance a reviewer will act on.
- **An in-sync index can still be inert.** `check` and `reachable` answer different questions, and a
  repository can pass the first while failing the second. Reporting "index in sync" without the
  reachability verdict is the exact false assurance the previous point warns about.
- **Rules discovery follows symlinks and does not require git.** A symlinked rule points outside the
  repository by design. That is the documented way to share one rule set across projects, so it is
  never tracked. Nested instruction files are the opposite: tracked-only, because an untracked or
  vendored `AGENTS.md` must never reach the consuming repository's always-loaded surface. If a rule
  seems missing from a report, check which of the two rules applies before assuming a bug.
