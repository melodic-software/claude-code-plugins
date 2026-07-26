# Gotchas — orchestrate

Observed failure modes for this skill and for the orchestration it arms. Each one cost something
real; none is inferable from the skill body alone.

## The nesting ceiling moves faster than the prose docs track it

Between 2026-06-09 and 2026-07-25 the subagent depth default went from a fixed five layers, to off,
to a configurable three. On 2026-07-26 the official `sub-agents` page still described the middle
state while the changelog and the running harness both had nesting on — so a tree authored from
either source alone could be wrong in **both** directions: assuming depth that is not there, or
declining depth that is. The failure is silent in the second direction, which is why it survives.

**Do this instead:** before committing a design to a second layer, have a worker of the **same agent
definition** you plan to use as the intermediate tier attempt a trivial nested spawn, and report the
exact outcome. Two ways this probe goes wrong if you shortcut it: stopping at "the `Agent` tool is
listed" (listing is necessary and not sufficient — a worker can hold the tool while the spawn is
refused), and probing with a different agent type (the gate is definition-specific, so a
`general-purpose` success says nothing about a definition that omits `Agent` or disallows it). That
second one is not hypothetical: it is the most likely explanation for the audit report that produced
this gotcha, which observed `Agent` "entirely absent" from a restricted agent type and read it as
nesting being off platform-wide. One cheap probe beats any citation — but it has to probe the thing
you are actually going to run. `context/sources.md` carries the verbatim quotes and the divergence.

## A denied spawn is not a depth answer

Subagent spawns are evaluated by the permission classifier *before* launch (changelog v2.1.178). A
refusal therefore says nothing about the depth ceiling, and reading it as "we are out of depth"
sends you into a redesign the platform never asked for. This bit the very probe that was measuring
the ceiling above — the depth question came back unresolved because a different gate answered first.
Read the error text: a depth rejection names depth, a permission rejection names permission.

## A clean return is not a correct return

An under-specified worker rarely stalls and asks — it substitutes the nearest plausible
interpretation and reports success in the same shape a correct worker would. See the eleven-worker
fan-out recorded under **Treat a clean return as unverified** in `SKILL.md`; the surviving rule is
that a return payload should name its sources, because provenance is the only field that makes a
wrong-target answer detectable from above.

## Priming is not emitting

The default action loads the imperatives into context and stops. Re-emitting them as paste text is
the most common misfire: it spends the window on output the session already has, and it reads as
having done the work. Only `handoff` / `worker` emit, and only for a target that LEAVES the session.
