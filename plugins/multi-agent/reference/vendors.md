# Vendor routing: which vendor, model and effort fit a task

Owner document for choosing between Claude, Codex and Gemini (through the Antigravity CLI, `agy`)
for one delegated task, and the model and effort for each. `/multi-agent:route vendors <task>`
follows it. Each CLI's flags, modes, model list and effort levels belong to the external-agents
plugin; this file reads them only through `external-agents models <product>`, never through that
plugin's files.

This file ships no model names. Every model and effort comes from the live listing or an upstream
page read at run time.

## The rule

1. **Default first.** For an everyday task, recommend each vendor's shipped default: for Claude,
   the role map (`/multi-agent:route <role>`); for Codex and Gemini, no `--model` and no
   `--effort`, so the CLI's own default runs. Basis: `default`.
2. **Go higher only for a heavy whole-task delegation**: a change across many files, a long
   unattended task, a hard bug in an existing codebase, or a security audit. Then raise effort one
   step above the vendor's default, or to the level the vendor's own effort guidance gives that
   kind of task, and keep the default model unless an upstream page or a benchmark below names a
   better one for this kind of task. Basis: the section or benchmark that supports the step.
3. **Never below the default for code.** Work that changes code, verifies a change or is likely to
   hit edge cases never gets a lower effort than the vendor's default.
4. **Only levels the CLI accepts.** A Codex or Gemini effort must appear in that product's
   `external-agents models` output (`efforts`, or the model's own `efforts`); a model must be one
   of its `models[].id`.

The caller passes the chosen values to `external-agents run` or `review` as `--model` and
`--effort` for that run only, and names the override and its basis in its reply.

## Task classes

| Class | Examples | Recommendation |
|---|---|---|
| everyday | a feature with a clear scope, a small fix, an investigation, a review of a normal change | each vendor's default |
| heavy | a change across many files, a long unattended task, a hard bug in an existing codebase, a security audit | effort one step up, default model unless a source names another |

When a task fits neither row, use `everyday` and say which part was unclear.

## Facts per vendor

- **Claude**: the role map from `/multi-agent:route <role>`, and the effort table in
  [model config: choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level)
  (its `high` row covers work where verification matters, its `max` row hard problems Claude works
  through without you).
- **Codex**: `external-agents models codex` (each model's `efforts` and `default_effort`), then
  [Models § Pick a reasoning effort](https://learn.chatgpt.com/docs/models#pick-a-reasoning-effort)
  and
  [Model selection § Find the right model for your workflow](https://learn.chatgpt.com/docs/model-selection#find-the-right-model-for-your-workflow).
- **Gemini**: `external-agents models antigravity` (its `models` and top-level `efforts`), then
  [Choose a model § Choose a model](https://antigravity.google/docs/models/#choose-a-model) and
  [Effort command](https://antigravity.google/docs/cli/commands/effort#inspect-or-override-effort-in-headless-mode).
  agy's model ids can carry their own effort word (`<model>-high`) beside `--effort`; which wins
  when both are given is not documented, so recommend one of the two, never both.

A product whose `external-agents models` output has a `status` other than `ok`, or a machine
without `external-agents`, gets no recommendation: the output names it as unavailable with the
reason, and covers the rest.

## Benchmarks

A benchmark supports a step above the default only when its page is read live during this run,
shows a date within the last 6 months, and lists the candidate models by name. Cite the page and
the rows read; a lead inside a row's stated error range is no lead. Read the scores live; this file
records none. A page the run cannot read (refused, empty, or not loaded) gives no support: the
reply names it as unread, never drops it silently.

| Benchmark | Page | Measures | Checked |
|---|---|---|---|
| Terminal-Bench 4.1 | [tbench.ai leaderboard](https://www.tbench.ai/leaderboard) | agents doing terminal tasks; each row names the agent harness (Claude Code, Codex, Antigravity CLI) and the effort it ran at | 2026-11-22: rows for Claude 5.5 and Fable 5.2, GPT-6.x and Gemini 4.x, model release dates up to Nov 18, 2026 |
| CursorBench 4.1 | [cursor.com/cursorbench](https://cursor.com/cursorbench) | agents on ambiguous multi-file tasks taken from real Cursor sessions | 2026-11-22: changelog entry Nov 18, 2026 (CursorBench 4.1); a vendor missing from its rows gets no support from it |
| WebDev Arena | `https://arena.ai/leaderboard/code/webdev` (written as code: it answers 403 to link checkers) | developers' head-to-head votes on built web apps; web front-end work only | 2026-11-22: page dated Nov 20, 2026, Claude, GPT and Gemini models in its top rows; it answers 403 to plain HTTP fetches, so read it with a browser-rendering scraper when the session has one |

Checked and not used on 2026-11-22: SWE-bench (no date on the page, no current models in the data
read), Artificial Analysis coding index and SWE-Bench Pro (no date shown), Aider polyglot (last
updated November 20, 2025), LiveCodeBench (leaderboard did not load).

- **Recheck trigger**: a listed page shows no date within 6 months, drops a vendor's current
  models, or moves; or a new benchmark covering all three vendors is proposed.

## Where to read the specifics

- **Pointer**: when the default effort of a Claude model is in question, fetch
  [model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level)
  live.
- **Pointer**: when deciding whether evidence justifies changing a model, fetch
  [choosing a model: decide whether to upgrade or change models](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model#decide-whether-to-upgrade-or-change-models)
  live.
