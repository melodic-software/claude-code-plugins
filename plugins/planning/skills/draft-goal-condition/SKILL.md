---
name: draft-goal-condition
description: "Routes the repetition-lever choice across /goal, /loop, routines and /schedule, a dynamic workflow, a Stop hook, and a one-shot prompt, then crafts a paste-ready /goal completion condition when /goal is the fit — the autonomous-goal / keep-working-toward-a-goal field Claude Code evaluates after every turn. Reads the current official docs live for the condition shape and character limit (never hardcodes either), drafts a transcript-demonstrable condition, and proves it fits the limit with a deterministic character counter instead of model guesswork, including a branch for goals no metric can measure. Use when: 'which loop should I use', '/goal or /loop', 'should this be a routine', 'should this be a workflow', 'pick the right autonomy lever', 'what kind of loop is this', 'craft a /goal', 'write a goal condition', 'set up an autonomous goal', 'make Claude keep working until X', 'my goal is not measurable', 'my /goal is too long / over the limit', 'turn this into a completion condition'."
argument-hint: "[intent]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: plan
  summary: Pick the right autonomy lever and craft a /goal completion condition
---

## Variables

Arguments: `$ARGUMENTS` — the natural-language intent for the autonomous run, plus any constraints or bounds the user volunteers.

## Purpose

Turn a stated intent into a paste-ready `/goal <condition>` string that conforms to the shape the official Claude Code docs prescribe and provably fits the documented character limit. A language model cannot reliably count characters, so length conformance is decided by a deterministic counter, not by estimation.

The `/goal` contract — its condition shape and its character limit — can change between Claude Code versions. This skill therefore reads the **current** official docs at authoring time and never bakes those values into its own text. The number you see in a doc today is not a constant to memorize.

## Step 0 — Lever fit (is `/goal` even the right tool?)

`/goal` starts the next turn when the previous one finishes and stops when a fresh evaluator model confirms a completion condition holds. Before authoring, confirm that fits the intent. If it does not, route instead of drafting:

- **Interval-driven** ("every 5 minutes", "poll until") → `/loop` (a time interval starts each turn), not `/goal`.
- **Cloud / sessionless / scheduled** ("nightly", "each morning", runs with no session open) → routines / `/schedule` (labelled research preview at the time of writing — check before recommending it).
- **Custom per-turn logic across all sessions** (deterministic script check, settings-scoped) → a prompt-based Stop hook.
- **More agents than one conversation can coordinate** (or the orchestration is worth codifying as a rerunnable script) → a dynamic workflow. Unlike the rows above, this one is not exclusive of `/goal`: a workflow decides how a single task fans out, `/goal` decides when to stop turning, and the two compose — the goal sets the hard completion requirement while the workflow performs the parallel work. Route away from drafting only when the intent wants the fan-out and *no* across-turn completion condition; when it wants both, draft the condition here and say the workflow rides alongside it.
- **One-shot** (a single prompt with no across-turn continuation) → just prompt; no goal.

Two caveats belong to the workflow row, because each turns a plausible recommendation into a dead one:

- **Route to the right ultracode form.** The `ultracode` keyword in a prompt runs **one** task as a workflow and changes nothing else — not the session's effort level — and is honored only from a prompt a human types (not `-p`, not an Agent SDK prompt that never stamps its origin as human input, not a scheduled-task prompt, not a webhook or relayed PR comment); asking in plain words — `use a workflow` — is the same opt-in. `/effort ultracode` is the separate standing setting: `xhigh` effort plus a workflow planned for each substantive task, for the rest of the session. Availability differs too — the workflow lever itself reaches all paid plans (on Pro it is switched on from the **Dynamic workflows** row in `/config`), while the standing setting needs a model that offers `xhigh` effort.
- **The lever is unreachable from an ordinary subagent.** The `Workflow` tool is filtered out of every non-fork subagent (`/discovery:research-deep` (if installed) exists because of this and documents it; the filter itself is on `https://code.claude.com/docs/en/sub-agents`). So a lever whose work lands in dispatched non-fork subagents — the loop lanes' dispatched workers, for instance — cannot be the workflow row however well it otherwise fits; recommend it only where the orchestrating context is the main thread or a fork.

Confirm the current comparison semantics against the live docs (below) rather than this summary — the routing table can drift, and the workflow row's availability and keyword specifics have each moved within recent releases. Only proceed when the intent genuinely wants "keep working until this condition is met."

## Step 1 — Read the live contract

Fetch the current official `/goal` documentation and extract, from the page itself:

1. the **effective-condition shape** it prescribes, and
2. the **maximum character limit** for a condition.

Primary source: `https://code.claude.com/docs/en/goal`. If Step 0 routing is in question, cross-check the scheduling comparison via the pages that doc links (`/en/scheduled-tasks`, routines) and the workflow row against `https://code.claude.com/docs/en/workflows`.

**Doc-fetch failure is not silent and never guessed.** If the page cannot be fetched or its structure has shifted so the limit or shape cannot be located, stop and tell the user exactly that, citing the URL. Do not fall back to a remembered number or shape — a stale limit or condition shape baked in here is precisely the drift this skill exists to avoid. Offer the user two ways forward: paste the current condition shape and character limit from that page — the shape drives the Step 2 draft, the limit drives the Step 3 counter — or defer until the docs are reachable. Never finalize a draft on a shape or limit that was not sourced live.

## Step 2 — Draft the condition

The evaluator judges the condition against **what Claude has already surfaced in the transcript** — it does not run commands or read files. Draft accordingly: every claim in the condition must be something Claude's own output can demonstrate.

Structure the draft to the shape Step 1 read off the live page — that page is the authority, and this file deliberately does not restate its elements. Keep each prescribed element separately identifiable in the draft, so Step 3's tightening pass can tell a load-bearing element from surrounding prose.

Avoid conditions the transcript cannot show (subjective quality, external state Claude never surfaces).

### When the outcome is not quantifiable

Most goals are not `npm test`. When the intent has no honest metric, do **not** manufacture one — a made-up number aims the evaluator at the wrong thing and lets a run pass on the wrong evidence. Three moves give the shape Step 1 read off the live page something demonstrable to be built out of; they feed that shape rather than replace it:

1. **A structural constraint** — something countable about the artifact: a length, a section count, one entry per input item.
2. **Enumerated required contents** — name the parts that must be present, so the evaluator decides "is it there" rather than "is it good".
3. **A self-verification sub-step that is itself checkable** — require the verifying *work*, not its verdict. "…a report where you have verified every citation by fetching it and confirming the page supports the claim" is checkable; "…a report whose citations are correct" is not.

Move 3 is what makes this branch work, and the no-tools constraint at the top of this step is why it has to be worded that way. The judgment is not self-review — it is delegated to a fresh-context evaluator model that receives only the condition and the conversation so far, and calls nothing — so the sub-step is credited only by verification Claude **performed in the transcript**. A claim that the checking happened reads identically to the checking having happened. Word it so the doing leaves visible output — the fetches, the diffs, the command runs — and the evaluator judges evidence rather than a promise.

Subjective quality still stays out of the condition. It re-enters only as whatever moves 1–3 made observable.

If the intent itself is still too vague to name a structure or a content list, settle it with `/planning:interview` before drafting — that skill owns the questioning; this one owns the condition.

## Step 3 — Mechanical length check

Validate the draft's character count against the **live limit from Step 1** with the deterministic counter (no model estimation). Write the draft to a temp file and pass `--file` — this is the robust path, immune to a condition that contains a single quote, backtick, or `$` that would otherwise mangle a piped string:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal-condition-length.sh" --limit <LIMIT_FROM_STEP_1> --file <path-to-draft>
```

For a simple condition with no shell-special characters, stdin also works: `printf '%s' "<condition>" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal-condition-length.sh" --limit <LIMIT_FROM_STEP_1>`.

Exit `0` = within limit, `1` = over, `2` = usage/env error (including a counter that failed to produce a number); stdout reports `chars=<n> limit=<N> status=<ok|over>`.

**On `status=over`:** tighten and re-run until it passes — shorten prose, fold overlapping elements together, drop redundant qualifiers — **without dropping any element the Step 1 shape prescribes**. If the intent genuinely cannot compress into one provable condition under the limit, say so rather than silently shedding a constraint; splitting a goal into sequential per-phase goals is not documented doctrine and is out of scope here.

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
