# Gotchas: orchestrate

Observed failure modes for this skill and for the orchestration it arms. Each one cost something
real; none is inferable from the skill body alone.

## The nesting ceiling moves faster than the prose docs track it

The subagent depth default has changed more than once within a few weeks, and the prose docs page
can lag the changelog by a release, so a tree authored from either source alone can be wrong in
both directions: assuming depth that is not there, or declining depth that is. The failure is
silent in the second direction, which is why it survives.

**Do this instead:** before committing a design to a second layer, have a worker of the **same
agent definition** you plan to use as the intermediate tier attempt a trivial nested spawn, and
report the exact outcome. Two ways this probe goes wrong if you shortcut it: stopping at "the
`Agent` tool is listed" (listing is necessary and not sufficient; a worker can hold the tool while
the spawn is refused), and probing with a different agent type (the gate is definition-specific,
so a `general-purpose` success says nothing about a definition that omits `Agent` or disallows
it). A restricted agent type that shows `Agent` as absent says nothing about nesting
platform-wide. One cheap probe beats any citation, but it has to probe the thing you are actually
going to run. `context/sources.md` carries the pointers, as-of dates, and recheck triggers.

## A denied spawn is not a depth answer

A permission gate can refuse a spawn *before* depth is consulted (record: `context/sources.md`,
"Imperative 5: NESTED SUBAGENTS"). We therefore read a refusal as saying nothing about the depth
ceiling; reading it as "we are out of depth" sends you into a redesign the platform never asked
for. A depth probe can come back unresolved because this
different gate answered first. Read the error text: a depth rejection names depth, a permission
rejection names permission.

## A clean return is not a correct return

An under-specified worker rarely stalls and asks. It substitutes the nearest plausible
interpretation and reports success in the same shape a correct worker would, so a wrong-target
result is indistinguishable from a right one by its return alone (see **Treat a clean return as
unverified** in `SKILL.md`). The rule: a return payload names its sources, because provenance is
the only field that makes a wrong-target answer detectable from above.

## Priming is not emitting

The default action loads the imperatives into context and stops. Re-emitting them as paste text is
the most common misfire: it spends the window on output the session already has, and it reads as
having done the work. Only `handoff` / `worker` emit, and only for a target that LEAVES the session.

## Unobservable rate-limit headroom is thin headroom, not free headroom

A session can have no live rate-limit reading: mods are off, `rate-limit-guard` is not installed,
a policy refused the `mcp__rate-limit-guard__status` tool's registration, or the tool answers with
no windows (`verdict: "unknown"`, as under API-key or enterprise auth), and there is no fresh
`~/.claude/rate-limit-guard/rate-limits.json` with `rate_limits`. Under `rate-limit-guard`'s reader contract that is
**unknown → reactive-only**, expected, not a setup bug. The failure mode is treating the missing
snapshot as "no pressure" and launching a wide fan-out that drains the same account-scoped windows
local sessions are pacing against, while sibling automation is already failing with
`429 rate-limit` and the orchestrator has no proactive signal to shrink further or to grow once
other sessions pause.

**Do this instead:** when no live reading is obtainable, imperative 7's rate-limit clause fires
the thin-by-default fallback (small concurrent cap, short waves, scale only on this session's own
rate-limit errors or live sibling-automation 429s). Do not invent window percentages. A later
reading with plausible windows restores proactive mode; until then the fallback applies.
