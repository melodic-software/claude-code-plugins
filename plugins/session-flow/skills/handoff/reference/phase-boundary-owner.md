# Phase-boundary save-point owner (#3952)

Option A: one owner. Dual-owner (handoff writes the artifact; dispatch owns continue) is parked.

## Decision record

- **Claim:** `/session-flow:handoff` is the single owner of the save-point artifact and of STOP.
  A resident `/implementation:implement-dispatch` phase boundary does not invoke this skill and
  does not write a handoff. Teaching handoff a resident / no-stop argument so dispatch can call
  it without ending the turn is unpaid and parked.
- **Basis:** Issue [#3952](https://github.com/melodic-software/claude-code-plugins/issues/3952).
  Origin/main `plugins/implementation/skills/implement-dispatch/SKILL.md` "The ritual scales with
  residency" and "Resident-vs-clear at phase boundaries": a resident boundary runs plan marks, a
  deviations entry, and the commit; the handoff entry exists for a session that restarts cold.
  This skill's "Hard rule. Handoff terminates the current execution" keeps STOP as the default.
  PR [#4741](https://github.com/melodic-software/claude-code-plugins/pull/4741) (#3711) already
  moved the *clear* ritual to invoke this skill last. The remaining ask in #3952 (a no-stop
  argument plus dispatch invoking it at every numbered boundary) is the dual-owner rebuild.
- **As of:** 2026-09-28.
- **Recheck:** a maintainer funds a no-stop argument on this skill, or `implement-dispatch`
  "Phase boundaries" again tells a resident orchestrator to write a handoff.

## Options

| Option | Scope | When to choose |
| --- | --- | --- |
| **A: Single owner (taken)** | Handoff owns the save-point and STOP. Resident dispatch records progress in plan marks and the commit, not in a handoff file | Current text already does this; this record names it |
| **B: Dual owner (parked)** | Handoff produces the artifact with a resident / no-stop argument; dispatch owns whether the session continues | Unpaid rebuild; either half alone leaves the conflict the issue named |

## Park

Do not add a resident / no-stop argument to this skill. Do not tell a resident orchestrator to
invoke `/session-flow:handoff` at each numbered phase. Track that rebuild under #3952 until a
maintainer funds it.
