---
description: "Pick the repetition lever (/goal, /loop, routines and /schedule, a workflow, a Stop hook, or a one-shot prompt) and, when /goal fits, draft a transcript-demonstrable completion condition, checked against the documented limit by a deterministic counter. Use when: 'which loop should I use', 'pick the right autonomy lever', 'craft a /goal', 'make Claude keep working until X', 'my goal is not measurable', 'my /goal is too long'."
argument-hint: "[intent]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: plan
  summary: Pick the right autonomy lever and craft a /goal completion condition
---

## Variables

Arguments: `$ARGUMENTS`. The natural-language intent for the autonomous run, plus any constraints or bounds the user volunteers.

## Purpose

Turn a stated intent into a paste-ready `/goal <condition>` string that conforms to the shape the official Claude Code docs prescribe and provably fits the documented character limit. A language model cannot reliably count characters, so length conformance is decided by a deterministic counter, not by estimation.

The `/goal` contract, its condition shape and its character limit, can change between Claude Code versions. This skill therefore reads the **current** official docs at authoring time and never bakes those values into its own text. The number you see in a doc today is not a constant to memorize.

## Step 0. Lever fit (is `/goal` even the right tool?)

`/goal` starts the next turn when the previous one finishes and stops when a fresh evaluator model confirms a completion condition holds. Before authoring, confirm that fits the intent. If it does not, route instead of drafting.

A lever that repeats build-and-check rounds (a metric hill-climb, or a `/goal`, `/loop` or routine that edits each round) pays off only when the task repeats and the agent can run what it builds and see the result. When either is missing, prompt once instead.

- **Metric hill-climb** (one editable target, a scorer the agent cannot edit, keep a round's change when the score improves and revert it otherwise, log every round) → no new runner. For runtime speed or a counter: `/performance:goal`, then `/performance:snapshot`, then `/performance:verify`. For a prompt or model setting against an eval suite: `/evals:methodology`, which says when the bundled `claude-api` skill's hillclimb fits and who starts it.

- **Interval-driven** ("every 5 minutes", "poll until") → `/loop` (a time interval starts each turn), not `/goal`.
- **Cloud / sessionless / scheduled** ("nightly", "each morning", runs with no session open) → routines / `/schedule`. Routines were labeled a research preview on `https://code.claude.com/docs/en/routines` as of 2026-09-02; re-read that label during the Step 1 fetch before recommending them, and recheck when the page drops the research-preview label.
- **Custom per-turn logic across all sessions** (deterministic script check, settings-scoped) → a prompt-based Stop hook.
- **More agents than one conversation can coordinate** (or the orchestration is worth codifying as a rerunnable script) → a dynamic workflow. Unlike the rows above, this one is not exclusive of `/goal`: a workflow decides how a single task fans out, `/goal` decides when to stop turning, and the two compose. The goal sets the hard completion requirement while the workflow performs the parallel work. Route away from drafting only when the intent wants the fan-out and *no* across-turn completion condition; when it wants both, draft the condition here and say the workflow rides alongside it.
- **One-shot** (a single prompt with no across-turn continuation) → just prompt; no goal.
- **Multi-window / multi-ticket** ("keep several sessions going", work that will not finish in one context window, a decomposed backlog) → when `work-items` is enabled: already-decomposed backlog / existing tickets → `/work-items:work` (or the work-loop); undecomposed plan or intent → `/work-items:decompose` then `/work-items:work`. When `work-items` is not enabled, tell the user to enable it (installing it first if needed). Or proceed to draft only if they insist on one-session completion. `/goal` keeps one session turning; a single goal-pursuing window relies on auto-compaction and spends most of its life degraded, while decomposed items each get a fresh window. Advisory routing default, not a prohibition. Proceed to draft when the intent is genuinely one-session completion.

Two caveats belong to the workflow row, because each turns a plausible recommendation into a dead one:

- **Route to the right ultracode form.** The `ultracode` keyword in a prompt runs **one** task as a workflow and changes nothing else, not the session's effort level, and is honored only from a prompt a human types (not `-p`, not an Agent SDK prompt that never stamps its origin as human input, not a scheduled-task prompt, not a webhook or relayed PR comment). Asking in plain words, `use a workflow`, is the same opt-in. `/effort ultracode` is the separate standing session setting that plans a workflow for each substantive task; for what it does to the effort level, see [Let Claude decide with ultracode](https://code.claude.com/docs/en/workflows#let-claude-decide-with-ultracode) (as of 2026-10-02; recheck when that section changes ultracode's effort interaction). Availability differs too. The workflow lever itself reaches all paid plans (on Pro it is switched on from the **Dynamic workflows** row in `/config`), while the standing setting needs a model that offers `xhigh` effort.
- **The lever is unreachable from an ordinary subagent.** The `Workflow` tool is filtered out of every non-fork subagent (`/discovery:research` (if enabled) selects its workflow-backed deep tier only in the main conversation for this reason; the filter itself is on `https://code.claude.com/docs/en/sub-agents`). So a lever whose work lands in dispatched non-fork subagents, the loop lanes' dispatched workers for instance, cannot be the workflow row however well it otherwise fits; recommend it only where the orchestrating context is the main thread or a fork.

Confirm the current comparison semantics against the live docs (below) rather than this summary. The workflow row's keyword, origin, and availability specifics above were verified against `https://code.claude.com/docs/en/workflows` and `https://code.claude.com/docs/en/sub-agents` on 2026-09-02; the Step 1 fetch is the recheck, and the live page wins over this text on any mismatch. Only proceed when the intent genuinely wants "keep working until this condition is met."

## Step 1. Read the live contract

Fetch the current official `/goal` documentation and extract, from the page itself:

1. the **effective-condition shape** it prescribes, and
2. the **maximum character limit** for a condition.

Primary source: `https://code.claude.com/docs/en/goal`. If Step 0 routing is in question, cross-check the scheduling comparison via the pages that doc links (`/en/scheduled-tasks`, routines) and the workflow row against `https://code.claude.com/docs/en/workflows`.

Read each page through the docs lookup: follow `${CLAUDE_PLUGIN_ROOT}/reference/docs-lookup-procedure.md` with `<scripts>` = `${CLAUDE_PLUGIN_ROOT}/scripts` and `<session>` = `${CLAUDE_SESSION_ID}`, fetch with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/fetch-docs.sh" --cache --max-age 0 --out <dir> goal` (the limit drives the Step 3 counter, so the bytes must be fresh), and take the sections you need with `docs-cache.sh` `slice`. Report the page's `validated` time with the draft. A page the manifest records `unread` was not fetched: read it with WebFetch instead only when the reason is `curl-missing` or the script wrote no manifest, and otherwise apply the failure rule below.

**Doc-fetch failure is not silent and never guessed.** If the page cannot be fetched or its structure has shifted so the limit or shape cannot be located, stop and tell the user exactly that, citing the URL. Do not fall back to a remembered number or shape. A stale limit or condition shape baked in here is precisely the drift this skill exists to avoid. Offer the user two ways forward: paste the current condition shape and character limit from that page. The shape drives the Step 2 draft, the limit drives the Step 3 counter. Or defer until the docs are reachable. Never finalize a draft on a shape or limit that was not sourced live.

## Step 2. Draft the condition

The evaluator judges the condition against **what Claude has already surfaced in the transcript**. It does not run commands or read files. Draft accordingly: every claim in the condition must be something Claude's own output can demonstrate.

Structure the draft to the shape Step 1 read off the live page. That page is the authority, and this file deliberately does not restate its elements. Keep each prescribed element separately identifiable in the draft, so Step 3's tightening pass can tell a load-bearing element from surrounding prose.

Avoid conditions the transcript cannot show (subjective quality, external state Claude never surfaces).

### When the outcome is not quantifiable

Most goals are not `npm test`. When the intent has no honest metric, do **not** manufacture one. A made-up number aims the evaluator at the wrong thing and lets a run pass on the wrong evidence. Three moves give the shape Step 1 read off the live page something demonstrable to be built out of; they feed that shape rather than replace it:

1. **A structural constraint**. Something countable about the artifact: a length, a section count, one entry per input item.
2. **Enumerated required contents**. Name the parts that must be present, so the evaluator decides "is it there" rather than "is it good".
3. **A self-verification sub-step that is itself checkable**. Require the verifying *work*, not its verdict. "…a report where you have verified every citation by fetching it and confirming the page supports the claim" is checkable; "…a report whose citations are correct" is not.

Move 3 is what makes this branch work, and the no-tools constraint at the top of this step is why it has to be worded that way. The judgment is not self-review. It is delegated to a fresh-context evaluator model that receives only the condition and the conversation so far, and calls nothing. So the sub-step is credited only by verification Claude **performed in the transcript**. A claim that the checking happened reads identically to the checking having happened. Word it so the doing leaves visible output. The fetches, the diffs, the command runs. And the evaluator judges evidence rather than a promise.

Subjective quality still stays out of the condition. It re-enters only as whatever moves 1–3 made observable.

If the intent itself is still too vague to name a structure or a content list, settle it with `/planning:interview` before drafting. That skill owns the questioning; this one owns the condition.

## Step 3. Mechanical length check

Validate the draft's character count against the **live limit from Step 1** with the deterministic counter (no model estimation). Write the draft to a temp file and pass `--file`. This is the robust path, immune to a condition that contains a single quote, backtick, or `$` that would otherwise mangle a piped string:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal-condition-length.sh" --limit <LIMIT_FROM_STEP_1> --file <path-to-draft>
```

For a simple condition with no shell-special characters, stdin also works: `printf '%s' "<condition>" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal-condition-length.sh" --limit <LIMIT_FROM_STEP_1>`.

Exit `0` = within limit, `1` = over, `2` = usage/env error (including a counter that failed to produce a number); stdout reports `chars=<n> limit=<N> status=<ok|over>`.

**On `status=over`:** tighten and re-run until it passes. Shorten prose, fold overlapping elements together, drop redundant qualifiers. **without dropping any element the Step 1 shape prescribes**. If the intent genuinely cannot compress into one provable condition under the limit, say so rather than silently shedding a constraint; splitting a goal into sequential per-phase goals is not documented doctrine and is out of scope here.

## Step 4. Output

Emit the final, counter-passed condition as a paste-ready invocation:

```text
/goal <condition>
```

When the `ProposeGoal` tool resolves in this session, also propose the condition through it under
the conditions the Boundary section below lists (no subagent, interactive local session, not plan
mode). The tool has its own, lower cap (500 characters on 2.1.285, per
[reference/native-goal.md](reference/native-goal.md)): re-run the Step 3 counter with
`--limit 500` first, and propose only a condition that passes it and contains no tab character
(the tool expands tabs before it counts, so the raw count would understate it). The paste-ready line above is
emitted either way.

Note for the user: `/goal` holds for the current session only. A goal survives `--resume` / `--continue` (though its turn count, timer, and token baseline reset), but running `/clear` removes it. So the goal must be re-set after any `/clear`.

## Boundary, the built-in `/goal` command and `ProposeGoal` tool

This skill exists to feed `/goal`, so the two are easy to mistake for one step. A built-in tool
can also put a drafted condition in front of the person.

- **`/goal` (built-in command)**: `/goal <condition>` sets a completion condition that a fresh
  evaluator checks before the session stops; `/goal clear` removes it, and bare `/goal` shows the
  current one. It is reserved for the person to run; the model does not invoke it.
- **`ProposeGoal` (built-in tool)**: the model proposes a goal condition and the person approves
  it with one keypress (`ask_user` true, the default); `ask_user` false sets it with no dialog.
  It cannot clear a goal, and it is refused in subagents, outside interactive local sessions, and
  in plan mode.
- **This skill (marketplace plugin).** Picks the right repetition lever and, when `/goal` fits,
  drafts a transcript-demonstrable condition sourced from the live docs and passed through the
  deterministic length counter. It sets nothing.

**Routing.** At the end of the run, always offer the paste-ready line: you can run
`/goal <condition>` with the drafted text, instead of or alongside continuing by hand. Also
propose it with `ProposeGoal`, leaving `ask_user` true, only when all of these hold: the tool
resolves in this session, the session is the main thread of an interactive local session (not a
subagent), plan mode is not active, and the condition passes the counter at the tool's own cap. When the lever check routes away from `/goal`, make
no offer. An unattended run records the paste-ready line in its output instead of asking.

**Mutation gate.** Only the person's approval arms a goal: their `/goal` run or their keypress on
a `ProposeGoal` dialog. This skill never sets `ask_user` false, and never sets, replaces, or
clears a goal on the person's behalf.

**Availability is never assumed.** This section states what to do when the person can run
`/goal` or `ProposeGoal` resolves, never that either is present in their host. The four-part
records live in [reference/native-goal.md](reference/native-goal.md).

## Gotchas

- **The limit is characters, not tokens.** The counter counts Unicode code points; do not substitute a token estimate.
- **Never hardcode the limit or the shape** into a draft, this file, or the script. They are read live each run; that is the whole point.
- **Over-limit submission behavior is undocumented**. There is no stated truncation or rejection semantics, so the pre-submission counter is the only guard. Do not assume the app will trim for you.
- **A long goal run draws usage on every turn.** We treat a goal left waiting on background work as still spending usage, so flag it when drafting a goal that waits on background work. Pointer: for why usage climbs in a long session and the setting that turns goal check-ins off, see <https://code.claude.com/docs/en/costs#why-usage-climbs-in-a-long-session>. As of: 2026-10-01. Recheck trigger: that section moves or stops naming goal check-ins.
- **A goal does not change permissions.** If the stated check runs a command, the user still gets asked unless auto mode or their settings already allow it. Worth flagging when the check is a shell command.
