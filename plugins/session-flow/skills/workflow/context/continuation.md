# End-of-phase continuation router

The stage map answers *what comes next*; this router answers *which continuation MECHANISM
carries the session there*. Run it at a phase boundary — a stage just produced its artifact — or
whenever "continue, clear, handoff, background, stop, or compact?" is the live question.

## Outcome set (derived, not inherited)

The terminals are exactly the continuation mechanisms this plugin installs plus the built-ins:
continue in session, `/clear`, `session-flow:handoff`, `session-flow:continue-in-background`,
`session-flow:clean-stop`, and `/compact`. Two session-flow siblings are deliberately NOT
terminals: `reconcile` and `orient` are state hygiene — they inform this decision (what is still
running, where we stand) but never carry the session forward. Mid-task subagent delegation is a
spawn-brief decision owned by `session-flow:orchestrate` (if installed), reached from question 1
only when the work leaves this session entirely.

## Zone input (presence-gated, conservative)

When the `context-guard` plugin is installed, resolve this session's zone word per its reader
contract (the contract owns the snapshot path, staleness rule, and bands — read them there; this
router consumes only the resulting word, and inlines no band values). Absent plugin, absent
snapshot, or `unknown` → assume degraded and lean on the judgment tests below (window position
and response quality). If context-guard's evidence-degraded marker exists for this session, or
the session is otherwise known to have been compacted, treat the context as degraded regardless
of a green zone word.

## The router — ask in order, first yes wins

Each edge carries its ordering purpose; an edge that loses its purpose is dead — remove it rather
than route past it.

0. **Is the machine going away (end of day, laptop shutting, runner expiring)?**
   → `session-flow:clean-stop`. *Asked first because a yes invalidates every local mechanism
   below: a handoff file is a machine-local save-point, and a save-point that dies with the disk
   is no save-point.* (Absent that skill: push everything durable by hand — commits, PR bodies,
   issue notes — before stopping.)
1. **Did the user explicitly request background continuation, AND can the work proceed without
   human input right now?** → `session-flow:continue-in-background`. *Ordered BEFORE every
   cost-based question below — including question 2's zero-cost in-session exit — on the same
   ground question 0 already establishes: a hard fact outranks a cost heuristic. Question 2 asking
   first would answer yes whenever context is healthy, silently discarding an explicit user
   instruction the user has no way of knowing was overridden; that is exactly the "edge that
   loses its purpose" this section warns against. It is also ordered BEFORE handoff because it is
   the strictly narrower gate on the same save-point engine — same state captured, different
   delivery (a detached background session instead of clear-then-paste). The explicit-request-
   and-feasibility gate is that skill's own hard rule, restated here only as an ordering fact; a
   background request that still needs human input, or that this session cannot hand off
   autonomously, is not this outcome and falls through to the questions below, most relevantly
   question 4 (handoff).*
2. **Is there enough smart zone left — or is the remaining work simple enough for a degraded
   context?** → continue in session. *The zero-cost exit for everything question 1 didn't already
   claim; every other remaining mechanism spends setup cost or loss. In a degraded zone only
   mechanical, low-judgment steps qualify as "simple enough".*
3. **Is this session's context disposable — nothing in it worth carrying forward?** → `/clear`.
   *The cheapest reset, asked before any writing mechanism: capturing state nothing needs is
   pure cost.*
4. **Must state survive the boundary — or does the work pass to another agent, another checkout,
   or a colleague?** → `session-flow:handoff`, then the user `/clear`s. *The first mechanism
   that pays a write cost without a live continuation attached: a handoff carries forward exactly
   the state that matters, chosen deliberately.* (Absent that skill: write a resume file by hand,
   then `/clear`.)
5. **Fallthrough** → `/compact`, at a phase boundary only, with a steering hint naming what the
   summary must keep. *Last deliberately: a compaction summary is a model-written lossy summary
   produced at the least-intelligent point of the session, and whatever degradation prompted
   this decision rides along into the continued session. The full tradeoff is owned by the
   handoff skill's "Fork beats compaction when the window is deep" section — this router routes;
   it does not restate.*

## Handoff-relay convention (workers)

For long-running delegated work, the same routing applies one level down, with a twist that keeps
the parent's window clean:

- A **worker** approaching its zone boundary writes its OWN handoff file (per the handoff
  engine's structure) and returns only the file PATH to its parent — never the contents.
- The **parent** spawns a successor worker briefed "Read that file, then continue its remaining
  next steps" — and never reads the handoff body itself. State passes worker → worker without
  ever occupying the parent's context window.

Spawn-brief discipline for workers (turn/budget caps, spec-every-spawn) is owned by
`session-flow:orchestrate` (if installed); without it, put the relay instruction directly in the
worker's spawn brief.
