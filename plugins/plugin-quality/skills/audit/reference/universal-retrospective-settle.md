# Post-use plugin retrospective is optional (#3999)

Option A: decline a universal wrap-up mandate. Keep `/plugin-quality:audit` operator-invoked.

## Decision record

- **Claim:** A post-use plugin retrospective is not a fleet wrap-up mandate. This skill stays
  optional and operator-invoked. Sessions that used a plugin skill are not owed an automatic
  offer, a workflow-skill route, or a new skill.
- **Basis:** Issue [#3999](https://github.com/melodic-software/claude-code-plugins/issues/3999)
  (overlap with this skill, `/session-flow:retro`, `/improvement:find`, `/overengineering:audit`,
  and `/discipline:*`). Interview comment on that issue (2026-09-11) recorded seven positions
  below; Q6's wrap-up offer through the workflow skill is the universal mandate this settle
  declines to ship. Reuse-or-replace already names this skill as the incumbent; a silent
  second way is the failure, not the divergence.
- **As of:** 2026-09-28.
- **Recheck:** an operator files a bounded issue to add wrap-up routing to
  `/session-flow:workflow`, or funds the session/arm extension the interview described as
  its own PR against this plugin.

## Interview positions (recorded, not shipping)

The 2026-09-11 interview accepted these as recommended. They are the parked Brief, not work
this record implements:

| Q | Position |
| --- | --- |
| 1 Shape | Extend this skill; no new skill |
| 2 When | Two operator-invoked entries (`session` at wrap-up, `arm` at start); none model-invoked; no hook |
| 3 Evidence | File only with a session artifact; research gate before agent-ready |
| 4 Discovery | Reuse the session-flow retro transcript parser; confirm targets |
| 5 Disciplines | Presence-gated seams by role; never a hardcoded list |
| 6 Threshold | Any session that invoked a plugin skill earns a wrap-up *offer* (declined as a mandate here) |
| 7 PR boundary | Build in its own PR, not with the code-metrics follow-ups |

## Options

| Option | Scope | When to choose |
| --- | --- | --- |
| **A: Optional incumbent (taken)** | Operator invokes `/plugin-quality:audit` when they want the pass | Current skill; no wrap-up routing |
| **B: Universal practice (parked)** | Workflow wrap-up offer plus session/arm modes | Unpaid; needs the interview's build PR |

## Park

Do not add wrap-up routing, `session`/`arm` actions, or a new retrospective skill in this
settle. Child [#4239](https://github.com/melodic-software/claude-code-plugins/issues/4239)
parks the matching audit scope expansion.
