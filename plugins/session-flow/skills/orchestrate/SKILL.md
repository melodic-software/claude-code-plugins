---
name: orchestrate
description: "Arm the CURRENT session for an orchestration-heavy task by loading seven proactive-orchestration imperatives (delegate/fan-out, spec-every-spawn, fresh-context verify, run-workers-well, nested subagents, surface drift, calibrate-to-conditions) as active standing instructions; optionally export them as a paste-ready brief for a spawned worker or fresh session. Use when: 'orchestrate', 'orchestration brief', 'prime this session', 'arm for orchestration', 'about to do heavy delegation', 'worker spawn prompt', 'delegation preamble'."
argument-hint: "[<task>] | handoff [compact] | worker [compact]"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Invoking this skill **arms the current session** for an orchestration-heavy task: it loads the
expanded seven-imperative operational form into active working context, and it declares deliberate
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
   explicit task boundaries, and a deliberately chosen model tier. Vague delegation makes workers
   duplicate each other, leave gaps, or wander; absent a consumer-level subagent-model override,
   an unspecified model silently inherits the parent session's — often its most expensive — model.
3. FRESH-CONTEXT VERIFY — after an edit batch or a finding set, hand it to a SEPARATE verifier;
   never self-audit in the context that produced it. Give the verifier concrete pass/fail criteria
   ("run the full suite, report all failures"), scope it to correctness/requirements (not style),
   and judge the final STATE, not the process — an uncriteriaed verifier just rubber-stamps. When
   the verdict is high-stakes, prefer a different-vendor advisor when one is set up and able to
   judge this artifact — its blind spots are uncorrelated with yours — with the fresh-context
   same-vendor verifier as the fallback.
4. RUN WORKERS WELL — prefer non-blocking dispatch: keep working while independent workers run.
   Reuse a long-lived worker across subtasks when your runtime supports it (saves cost via cache).
   Watch running workers and intervene the moment one drifts or is missing context.
5. NESTED SUBAGENTS — a worker may spawn its own workers when a delegated task itself subdivides
   AND the depth is non-load-bearing. This is a shipped feature, not experimental — but reliability
   degrades with depth and platforms cap it, so never author a tree that needs a specific or deep
   nesting level.
6. SURFACE DRIFT — the moment you notice a stale reference, broken citation, or convention
   conflict adjacent to your task, flag it in one line; don't fix it silently, don't deep-dive.
7. CALIBRATE TO CONDITIONS — size the whole orchestration (whether to delegate at all, fan-out
   width, nesting depth) to the conditions in play, never a fixed recipe: the active model's
   capability (a stronger model reaches further single-agent; a weaker one needs more decomposition
   and tighter specs), whether a capable advisor/verifier is on hand, current context pressure
   (delegate to protect a filling window; stay inline when it is roomy), and concurrent-session load
   / rate-limit headroom (thin headroom caps how many workers you run at once). Sizing is
   small/medium/large — a small ask stays single-agent, a medium one fans out a few, only a large
   genuinely-independent surface earns a wide or nested tree. Single-agent is the floor, not the
   fallback. Per-worker tier is part of sizing and scales with fan-out width: past a wide fan-out
   the cheaper tier becomes the DEFAULT the whole fleet inherits — volume multiplies every notch
   of over-provisioning — and the standing exception is an explicitly hard stage (verify,
   judge/adjudicate, judgment-heavy synthesis), which keeps the parent tier. Tier is not only the
   model: match the reasoning depth (effort) to the subtask too, not the parent session —
   high-volume mechanical work (search, extraction, per-item transforms, formatting) runs cheaper
   on both. A premium fan-out outside the hard stages is a per-stage decision to justify
   explicitly, never a default to inherit.

Discipline: trigger-evaluation is mandatory; the ACTION stays calibrated (delegate on value +
parallelism, not convenience). Treat every worker's return as unverified synthesis — verify
load-bearing claims against a primary source before acting. Cite sources you actually fetched;
never label a claim "known" / "from memory" / "obvious".

**Priming addendum (current session only).** As the main session — not a spawned worker — you may
also reach orchestration surfaces a worker cannot: agent teams (lead-only) and dynamic workflows
(main-session-only). The export modes omit this line because a pasted target cannot reach those
surfaces.

## Tiered delegation — the shape of a deep tree

Imperative 5 says a worker may spawn workers and imperative 7 says size the tree to conditions.
This section is the shape those two imply once a task is large enough to need more than one layer.
It is guidance for the main session; the export brief omits it, because a pasted worker sits inside
a tree rather than authoring one.

**The top of the tree owns the loop, not the work.** Its context is the scarcest in the run —
everything that enters it stays for the rest of the session. So it holds the objective, the
stopping condition, and the decision about what to spawn next, and it delegates the rest. A top
tier that reads findings, weighs them, and asks a follow-up question has converted a fan-out into a
conversation, and the context it was protecting fills anyway.

**Chatter belongs low.** Two workers resolving an ambiguity between themselves costs nothing at the
top. The same exchange routed through the parent costs the parent's window twice and permanently.
Push coordination to the lowest tier that can resolve it, and let each tier return a compressed
verdict rather than its reasoning.

**Spec what crosses a boundary, not just what to do.** Every spawn already needs an objective and
an output format (imperative 2). In a multi-tier tree the output format IS the context-economy
lever: name the identifiers, the verdict, and where the bulky payload was parked, so the tier above
can act without re-reading the work. A return that narrates cannot be summarized after the fact —
it has already been paid for.

**Workers are ephemeral, and the deeper the tier the shorter the life.** A worker that finishes and
stays alive keeps costing the tier above — notifications, status, re-acknowledgement — for zero
additional output. Retire on completion. When the next grouping needs doing, spawn fresh rather than
reusing a worker whose context now carries the last job. (The exception is imperative 4's long-lived
worker across *related* subtasks, where cache reuse is the point — that is a deliberate trade, not
the default.)

**Treat a clean return as unverified, especially a suspiciously clean one.** An under-specified
worker rarely stalls and asks; it substitutes the nearest plausible interpretation and reports
success. Observed in this plugin's own development: a fan-out of eleven audit workers was given a
brief missing a resource they needed. Ten located it themselves and closed the gap; one silently
audited a different, similar artifact and returned a confident, well-formed, entirely
wrong-target result. Nothing in its return distinguished it from the ten. This is why imperative 3's
fresh-context verify is not optional at depth, and why a return payload benefits from naming its
sources — provenance is the field that makes a wrong-target answer detectable from above.

**Never author a tree that needs a specific depth.** The platform ceiling is configurable and has
moved repeatedly — within a single week it went from a fixed five layers, to nesting off by
default, to a configurable default of three
([sub-agents](https://code.claude.com/docs/en/sub-agents),
[changelog](https://code.claude.com/docs/en/changelog)). Depth, per-session spawn count, and
concurrent-worker count are each separately capped and separately overridable
(`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`,
`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`); read the current values rather than assuming them, and
design the tree so it degrades to a shallower one instead of failing. One shape constraint that is
not a tunable: a fork inherits its parent's conversation but cannot spawn a further fork, so a fork
is a leaf, never an intermediate tier.

## Export modes (handoff / worker) — paste-ready brief

Only for a target that LEAVES the session. Emit the seven imperatives above between two full-width
`─` (U+2500) dashed rails — top rail, brief, bottom rail, nothing else between them; the
`/clear`/paste instruction or any commentary sits above the top rail or below the bottom rail,
never between (NOT a code fence — the user copies the text between the rails, not fence markers).

Live shape: bare `─` rails, no fence — shown inside a fence here for display only.

```text
──────────────────────────────────────────────────────────
ORCHESTRATION BRIEF — standing instructions for the whole task, regardless of which model or tool runs you.

At each decision boundary, evaluate these and ACT on a match without waiting to be told:
[the seven numbered imperatives above, verbatim]

Discipline: [the Discipline line above, verbatim]
──────────────────────────────────────────────────────────
```

- `handoff` — the opening line above already fits a fresh session; emit as-is.
- `worker` — insert as the FIRST line between the rails: `You are a spawned worker and did NOT
  inherit the parent session's context or the repo's conditional rules — these instructions are
  your only copy.`
- `compact` — emit only the seven numbered HEADLINES (`1. DELEGATE / FAN OUT`, `2. SPEC EVERY
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
