---
name: orchestration-brief
description: "Arm the CURRENT session for an orchestration-heavy task by loading six proactive-orchestration imperatives (delegate/fan-out, spec-every-spawn, fresh-context verify, run-workers-well, nested subagents, surface drift) as active standing instructions; optionally export them as a paste-ready brief for a spawned worker or fresh session. Use when: 'orchestration brief', 'prime this session', 'arm for orchestration', 'about to do heavy delegation', 'worker spawn prompt', 'delegation preamble'."
argument-hint: "[<task>] | handoff [compact] | worker [compact]"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Invoking this skill **arms the current session** for an orchestration-heavy task: it loads the
expanded six-imperative operational form into active working context, and it declares deliberate
intent to orchestrate the work about to start, so the triggers get evaluated actively rather than
sitting passively in background rules. That is the default — no paste, no rails, just preloaded
context.

The same imperatives also **export** as a self-contained, paste-ready brief for targets that LEAVE
the session and therefore inherit none of its context: a spawned subagent/teammate, a fresh session
you will `/clear` into, or a non-Claude-Code tool. Export is model- and tool-agnostic by
construction — nothing in the pasted text depends on a specific model, env var, or repo file.

The official sources and quotes behind each imperative: `context/sources.md` (read only when
judging a coverage question or extending the skill).

## Actions

| Action | What it does |
|---|---|
| *(default — optional `<task>`)* | **Prime THIS session.** The standing instructions below are now active for the upcoming task; respond with a terse acknowledgment and, if `<task>` is given, one line orienting to it. Do NOT re-emit the imperatives — loading them IS the priming. |
| `handoff [compact]` | **Export** the imperatives as a paste-ready dashed-rail brief framed for a fresh session. `compact` = headlines only. |
| `worker [compact]` | **Export** framed for a spawned worker (prepends the did-not-inherit-context line). `compact` = headlines only. |

## Orchestration imperatives — standing instructions

At each decision boundary in this task, evaluate these and ACT on a match without waiting to be
told:

1. DELEGATE / FAN OUT — start with one agent (a single agent goes further than you expect);
   delegate only when work would flood context, fans across genuinely independent paths, or needs a
   tool-restricted specialist. Decompose by what CONTEXT each piece needs, not by head-count or
   work-type — sequential or shared-context steps stay in one agent. Coding parallelizes less than
   research: never split one feature across agents. Multi-agent costs 3–10× the tokens (returns
   cost context too), so spend it on value + parallelism, not convenience.
2. SPEC EVERY SPAWN — give each worker an objective, an output format, the tools/sources to use,
   and explicit task boundaries. Vague delegation makes workers duplicate each other, leave gaps,
   or wander.
3. FRESH-CONTEXT VERIFY — after an edit batch or a finding set, hand it to a SEPARATE verifier;
   never self-audit in the context that produced it. Give the verifier concrete pass/fail criteria
   ("run the full suite, report all failures"), scope it to correctness/requirements (not style),
   and judge the final STATE, not the process — an uncriteriaed verifier just rubber-stamps.
4. RUN WORKERS WELL — prefer non-blocking dispatch: keep working while independent workers run.
   Reuse a long-lived worker across subtasks when your runtime supports it (saves cost via cache).
   Watch running workers and intervene the moment one drifts or is missing context.
5. NESTED SUBAGENTS — a worker may spawn its own workers when a delegated task itself subdivides
   AND the depth is non-load-bearing. This is a shipped feature, not experimental — but reliability
   degrades with depth and platforms cap it, so never author a tree that needs a specific or deep
   nesting level.
6. SURFACE DRIFT — the moment you notice a stale reference, broken citation, or convention
   conflict adjacent to your task, flag it in one line; don't fix it silently, don't deep-dive.

Discipline: trigger-evaluation is mandatory; the ACTION stays calibrated (delegate on value +
parallelism, not convenience). Treat every worker's return as unverified synthesis — verify
load-bearing claims against a primary source before acting. Cite sources you actually fetched;
never label a claim "known" / "from memory" / "obvious".

**Priming addendum (current session only).** As the main session — not a spawned worker — you may
also reach orchestration surfaces a worker cannot: agent teams (lead-only) and dynamic workflows
(main-session-only). The export modes omit this line because a pasted target cannot reach those
surfaces.

## Export modes (handoff / worker) — paste-ready brief

Only for a target that LEAVES the session. Emit the six imperatives above between two full-width
`─` (U+2500) dashed rails — top rail, brief, bottom rail, nothing else between them; the
`/clear`/paste instruction or any commentary sits above the top rail or below the bottom rail,
never between (NOT a code fence — the user copies the text between the rails, not fence markers).

Live shape: bare `─` rails, no fence — shown inside a fence here for display only.

```text
──────────────────────────────────────────────────────────
ORCHESTRATION BRIEF — standing instructions for the whole task, regardless of which model or tool runs you.

At each decision boundary, evaluate these and ACT on a match without waiting to be told:
[the six numbered imperatives above, verbatim]

Discipline: [the Discipline line above, verbatim]
──────────────────────────────────────────────────────────
```

- `handoff` — the opening line above already fits a fresh session; emit as-is.
- `worker` — insert as the FIRST line between the rails: `You are a spawned worker and did NOT
  inherit the parent session's context or the repo's conditional rules — these instructions are
  your only copy.`
- `compact` — emit only the six numbered HEADLINES (`1. DELEGATE / FAN OUT`, `2. SPEC EVERY
  SPAWN`, …) plus the closing Discipline line; drop every sub-clause.

## What this skill does NOT do

- **Default does not emit paste-text.** Priming the current session is a terse acknowledgment —
  the work happens because the imperatives loaded into context, not because anything was printed.
  Use `handoff` / `worker` only when the target LEAVES the session.
- **Not a surface-selection guide.** Which parallel-execution surface to pick (subagents vs nested
  vs teams vs workflows) is a judgment the main session makes against current official docs; the
  export brief deliberately omits agent teams + dynamic workflows because a spawned worker cannot
  reach either.
- **Does not delegate, verify, nest, or spawn anything itself** — it arms the session or emits
  instruction text.
