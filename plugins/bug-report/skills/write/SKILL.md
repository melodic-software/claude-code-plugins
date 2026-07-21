---
name: write
description: "Produce a structured 5-field bug report (title, steps to reproduce, expected vs actual, severity with justification, suggested fix location) from an informal description. Read-only — never modifies code, never opens PRs, never files issues by default. Use when: 'there is a bug in <X>', 'report a bug', 'file a bug', 'bug-report this', '<symbol> gives wrong output when <condition>', 'I am seeing <error> in <file>', 'expected X got Y', 'write this up as a bug'. Skip when: deep investigation is needed, a fix is already in progress, or the request is a feature request (missing capability) rather than a defect. Emits Markdown to stdout by default; with --file, persists a report file and can hand off to a work-item tracker for filing."
argument-hint: "[--file] [--quick|--full] [--no-survey] <bug description>"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree: !`git status --porcelain 2>/dev/null | head -5 || echo "clean"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

`/bug-report` produces a five-field structured report so the next session (or a human) can act without re-asking on vague repro, missing severity, no fix location, or hand-wavy expected/actual. **Read-only** — it captures, it does not fix, and it does not file (unless you explicitly ask).

This is the **bug-intake** stage. It sits upstream of filing the report into a work-item tracker, and it is independent of any downstream fix workflow — when the report itself is the deliverable (a Slack message, a PR comment, a verbal handoff), that is all this skill needs to do.

Five fields: title, steps to reproduce, expected vs actual, severity (with justification), and suggested fix location. A `(unknown — needs reporter confirmation)` placeholder is used for any field that cannot be backed from the source, rather than inventing one.

A sharp report captured up front saves the next session from re-asking. Unrepresented reproduction steps cost far more to recover later than to capture now.

## Trigger conditions — when to invoke

Invoke when ANY hold:

- The user describes a defect ("there is a bug in `X`", "`X` is broken when `Y`")
- The user asks for help filing/writing-up a bug ("how do I report this", "write this up")
- The user states a behavioural mismatch ("expected `X`, got `Y`", "`X` returns wrong value when `Y`")
- The user asks for a structured report from informal context

## Skip conditions — when to NOT invoke

- **Investigation needed** — the bug needs reproduce-first diagnosis, not just capture. If your project provides a debugging or investigation skill, hand off to it; otherwise scope the investigation separately from this read-only capture.
- **Fix already in progress** — this skill only captures; it does not complete a fix.
- **Feature request** (a missing capability, not a defect) — this is product intent, not a bug. If your project provides a PRD or requirements-intake skill, route there; otherwise capture it as a feature request, not a five-field bug report.
- **Generic chore** (a TODO, docs gap, or non-defect task) — file it directly in your tracker; it does not need the five-field bug shape.

If it is ambiguous, surface the question once and let the user pick.

## The bug-report process

### Step 1 — Skip-condition check (MANDATORY)

If the request matches a skip condition, STOP and recommend the right path. Do not produce a bug report for a feature request, an investigation task, or a generic chore.

### Step 2 — Survey before you write

A fast breadth pass before deep work. In parallel:

- `Glob`/`Grep` for the symbol named in the description (function, class, file, error message)
- If more than one symbol matches, the description is ambiguous — ask which one
- `git log --oneline -10 -- <suspected-file>` if a file is named — a recent change may be the cause
- Check the output directory (see Step 4) for prior bug reports on the same area, to avoid duplicates

Skip the survey when `--no-survey` was passed (unconditionally — the flag means "trust the description"), or when `--quick` was passed AND the description names a single unambiguous symbol.

### Step 3 — Targeted Q&A

Ask ONE question at a time. Use `AskUserQuestion` when 2-4 named options exist (e.g. "which `flush()` — there are 3 in the repo: …"); use prose for open-ended questions.

Question priority order — only ask if the field cannot be backed from context:

| Field | Highest-value question |
|-------|------------------------|
| Steps to reproduce | "Walk me through the smallest sequence that triggers it." |
| Expected vs actual | "What did you expect? What did you see instead?" |
| Severity | "Who or what is blocked? Production users / dev workflow / cosmetic?" |
| Fix location | (do not ask — derive from the survey; if unknown, mark `(unknown — needs reporter confirmation)`) |
| Title | (do not ask — derive from symptom + symbol) |

Stop conditions: every required field has a backed answer OR an explicit `(unknown — needs reporter confirmation)` placeholder. Modifiers:

| Flag | Effect |
|------|--------|
| (none) | Survey + targeted Q&A; default to `--full` discipline if the symbol is ambiguous |
| `--quick` | Skip the survey if the symbol is unambiguous; max 1 round of Q&A |
| `--full` | Always survey; up to 3 rounds of Q&A |
| `--no-survey` | Trust the description; only ask when a field would otherwise be invented |
| `--file` | Write the report to a file (see Step 4) instead of only stdout; then offer to file it in a tracker |

### Step 4 — Emit the report

Default: emit Markdown to stdout (read-only). Follow the 5-field template — see [`context/template.md`](context/template.md) for the full structure with a worked example.

`--file` mode: write the report to a file with frontmatter `type: bug-report`. Resolve the output directory in this precedence, and always tell the user the final path:

1. If the consumer configured `output_dir`, write to `${user_config.output_dir}`.
2. Otherwise, write to `${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`, where `<project-slug>` is the kebab-cased basename of the project root (`${CLAUDE_PROJECT_DIR}`, or the git toplevel when unset). The plugin data directory is per-plugin, not per-project — without the slug, Step 2's duplicate scan would match another repository's report on the same symbol.
3. If neither resolves, fall back to `${CLAUDE_PROJECT_DIR}/.bug-reports/` and state clearly where the file landed.

Filename: derive a slug from the title (kebab-case, ~40-char cap), prefix an ISO basic UTC timestamp with no colons (Windows-safe), e.g. `20260502T143000Z-bug-pricefor-discount-math.md`. If the title cannot yet produce a slug, fall back to the timestamp alone.

### Step 5 — Hand off

After emitting the report, recommend the next step (do NOT auto-invoke):

- **File it as a work item** — if you are in a GitHub repository and the `gh` CLI is available. `--body-file` needs a report file on disk: in `--file` mode use the emitted report path; in default stdout mode first save the report (offer to re-run the write step or Write it to a temp file). Then run `gh issue create --body-file <report>` and let `gh` prompt for the title interactively. If filing non-interactively, never interpolate the reporter's title text into the command string — write the title to a file first, then run `gh issue create --title "$(cat <title-file>)" --body-file <report>`: the command-substitution RESULT is a quoted argument value and is not re-parsed, so backticks or `$( )` inside the reporter's text cannot execute. If a work-item tracker MCP tool is available, use it. Map the severity to your tracker's priority labels if it has them.
- **A fix is next** — if your project provides an investigation or implementation workflow, route there; otherwise scope the fix separately.
- **The report is the deliverable** (Slack, PR comment, hand-off) — done; copy/paste the stdout.

## Severity rubric

Severity is `low / medium / high / critical` with a one-line justification. It is not "how upset is the reporter" — it is blast radius × blocking factor × data-integrity impact:

| Severity | Use when |
|----------|----------|
| `critical` | Production data corruption, security breach, full-app outage, money-affecting math bug |
| `high` | Feature broken for a large share of users, blocking dependent work, affects a core flow |
| `medium` | Feature broken for a narrow case, has a workaround, edge-case data issue |
| `low` | Cosmetic, documentation, dev-experience, or tooling drift |

If a tracker uses priority labels (e.g. `p0`/`p1`/`p2`/`p3` or `priority:high`), map this rubric onto them when filing. If severity cannot be calibrated from context, ask ONE question — do not invent it.

## What this skill does NOT do

- **Does not write code or open a PR.** It produces a report only.
- **Does not invent reproduction steps.** If a step cannot be backed from the source, a test, or the reporter's description, it is marked `(unknown — needs reporter confirmation)` and surfaced under Notes. Flag a gap rather than fabricate one.
- **Does not file the report by default.** The user reads the report and decides. `--file` persists it; filing into a tracker is an explicit hand-off in Step 5.
- **Does not investigate the bug.** Step 2's survey is a fast grounding pass, not deep work. A fix that needs real investigation should be scoped separately.
- **Does not auto-fix typos in the user's description.** "There is a bug in `flusH()`" may be intentional in some languages — ask one question.
- **Does not run a broad exploration or research pass.** If a fix needs deep investigation, recommend scoping it separately rather than doing it here.

## Gotchas

- **Repro steps must be backed.** If you cannot derive them from the user's description, the source, or a test, mark `(unknown — needs reporter confirmation)`. Inventing repro is worse than admitting a gap.
- **Severity is blast radius, not frustration.** Use the rubric; justify in one sentence.
- **Suggested fix location is not a patch.** Name the file path and function/class. No code, no diff, no "just change line X to Y". The fixer decides the patch.
- **Title in present tense.** "`priceFor` returns wrong total when `discountPercent` is non-zero" — not "fixed pricing bug" or "pricing was broken".
- **When there is no bug, do not emit a report.** If the survey and Q&A reveal the behaviour is correct, emit the short "No bug confirmed" summary instead (see `context/template.md`).

## Cross-references

- [`context/template.md`](context/template.md) — full Markdown template, worked example, `--file` frontmatter, and the "No bug confirmed" form
- Consumer conventions (naming, areas, priority labels, tracker choice) come from the consuming project's own `CLAUDE.md` / rules — this skill reads them rather than imposing its own
