---
name: draft-goal-condition
description: "Craft a paste-ready /goal completion condition from a stated intent — the autonomous-goal / keep-working-toward-a-goal field Claude Code evaluates after every turn. Reads the current official /goal docs live for the condition shape and character limit (never hardcodes them), drafts a transcript-demonstrable condition (measurable end state + stated check + constraints + optional turn/time bound), and proves it fits the limit with a deterministic character counter instead of model guesswork. Use for 'craft a /goal', 'write a goal condition', 'set up an autonomous goal', 'make Claude keep working until X', 'my /goal is too long / over the limit', 'turn this into a completion condition'; skip and route elsewhere when the work is interval-shaped (/loop), cloud/sessionless (routines, /schedule), or a one-shot prompt."
argument-hint: "[intent]"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS` — the natural-language intent for the autonomous run, plus any constraints or bounds the user volunteers.

## Purpose

Turn a stated intent into a paste-ready `/goal <condition>` string that conforms to the shape the official Claude Code docs prescribe and provably fits the documented character limit. A language model cannot reliably count characters, so length conformance is decided by a deterministic counter, not by estimation.

The `/goal` contract — its condition shape and its character limit — can change between Claude Code versions. This skill therefore reads the **current** official docs at authoring time and never bakes those values into its own text. The number you see in a doc today is not a constant to memorize.

## Step 0 — Lever fit (is `/goal` even the right tool?)

`/goal` starts the next turn when the previous one finishes and stops when a fresh evaluator model confirms a completion condition holds. Before authoring, confirm that fits the intent. If it does not, route instead of drafting:

- **Interval-driven** ("every 5 minutes", "poll until") → `/loop` (a time interval starts each turn), not `/goal`.
- **Cloud / sessionless / scheduled** ("nightly", "each morning", runs with no session open) → routines / `/schedule`.
- **Custom per-turn logic across all sessions** (deterministic script check, settings-scoped) → a prompt-based Stop hook.
- **One-shot** (a single prompt with no across-turn continuation) → just prompt; no goal.

Confirm the current comparison semantics against the live docs (below) rather than this summary — the routing table can drift. Only proceed when the intent genuinely wants "keep working until this condition is met."

## Step 1 — Read the live contract

Fetch the current official `/goal` documentation and extract, from the page itself:

1. the **effective-condition shape** it prescribes, and
2. the **maximum character limit** for a condition.

Primary source: `https://code.claude.com/docs/en/goal`. Cross-check the scheduling comparison via the pages that doc links (`/en/scheduled-tasks`, routines) if Step 0 routing is in question.

**Doc-fetch failure is not silent and never guessed.** If the page cannot be fetched or its structure has shifted so the limit or shape cannot be located, stop and tell the user exactly that, citing the URL. Do not fall back to a remembered number — a stale limit baked in here is precisely the drift this skill exists to avoid. Offer the user two ways forward: paste the current character limit from that page so the counter (Step 3) can run, or defer until the docs are reachable. Never finalize a draft without a limit sourced live.

## Step 2 — Draft the condition

The evaluator judges the condition against **what Claude has already surfaced in the transcript** — it does not run commands or read files. Draft accordingly: every claim in the condition must be something Claude's own output can demonstrate.

Structure the draft to the doc-sourced shape. As of the contract this skill targets, that is:

- **One measurable end state** — a test result, a build exit code, a file count, an empty queue.
- **A stated check** — how Claude proves it (e.g. "`npm test` exits 0", "`git status` is clean").
- **Constraints that must not change** on the way there (e.g. "no other test file is modified").
- **An optional turn/time bound** — e.g. "or stop after 20 turns" — to cap runaway loops.

Avoid conditions the transcript cannot show (subjective quality, external state Claude never surfaces).

## Step 3 — Mechanical length check

Validate the draft's character count against the **live limit from Step 1** with the deterministic counter (no model estimation):

```shell
printf '%s' "<drafted condition>" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal-condition-length.sh" --limit <LIMIT_FROM_STEP_1>
```

`--file <path>` reads the condition from a file instead of stdin. Exit `0` = within limit, `1` = over, `2` = usage/env error; stdout reports `chars=<n> limit=<N> status=<ok|over>`.

**On `status=over`:** tighten and re-run until it passes — shorten prose, fold the stated check into the end state, drop redundant constraints — **without dropping the measurable end state, the stated check, or the load-bearing constraints**. If the intent genuinely cannot compress into one provable condition under the limit, say so rather than silently shedding a constraint; splitting a goal into sequential per-phase goals is not documented doctrine and is out of scope here.

## Step 4 — Output

Emit the final, counter-passed condition as a paste-ready invocation:

```text
/goal <condition>
```

Note for the user: `/goal` holds for the current session only. A goal survives `--resume` / `--continue` (though its turn count, timer, and token baseline reset), but running `/clear` removes it — so the goal must be re-set after any `/clear`.

## Gotchas

- **The limit is characters, not tokens.** The counter counts Unicode code points; do not substitute a token estimate.
- **Never hardcode the limit or the shape** into a draft, this file, or the script. They are read live each run; that is the whole point.
- **Over-limit submission behavior is undocumented** — there is no stated truncation or rejection semantics, so the pre-submission counter is the only guard. Do not assume the app will trim for you.
- **A goal does not change permissions.** If the stated check runs a command, the user still gets asked unless auto mode or their settings already allow it — worth flagging when the check is a shell command.
