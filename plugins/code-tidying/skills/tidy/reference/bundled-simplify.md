# The bundled `simplify` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The sibling `batch-simplify` skill keeps its own record against the same
surface in [../../batch-simplify/context/bundled-simplify.md](../../batch-simplify/context/bundled-simplify.md).

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `simplify` ships with Claude Code as a bundled skill with no alias, invoked as `/simplify [target]`: "Review the changed code for cleanup opportunities and apply the fixes. Four review agents run in parallel, covering reuse of existing helpers, simplification, efficiency, and whether the change is at the right level of abstraction. The review doesn't look for correctness bugs. Use `/code-review` to find bugs. Pass a path or PR reference to review a specific target" | The `/simplify` row on <https://code.claude.com/docs/en/commands>, labeled Skill | 2026-09-11 | The row changes its targets or flags, or gains an alias |
| Its registered description reads "Review the changed code for reuse, simplification, efficiency, and altitude cleanups, then apply the fixes. Quality only, it does not hunt for bugs; use /code-review for that", menu line "Clean up the changed code without changing behavior" | String search of the installed 2.1.263 binary | 2026-09-11 | A release changes the registration text |
| It mutates by default. The binary's description says "then apply the fixes" and the commands row says "apply the fixes"; neither documents a flag that turns applying off | The two rows above | 2026-09-11 | Either source introduces a report-only mode |
| It is diff-anchored: the target is the changed code, or a path or PR reference, always something that already changed | The commands row; the code-review page: "`/simplify` runs a separate cleanup-only review that applies fixes without hunting for bugs" (<https://code.claude.com/docs/en/code-review>) | 2026-09-11 | The skill gains a mode that hunts a scope independent of recent changes |

## Why the verdict is complementary

Both surfaces clean code without changing behavior. They differ in anchor: `/simplify` refines a
diff that exists, and tidy hunts unfiled drift across a glob-scoped lane regardless of recent
activity, under a scope budget, shipping one structure-only PR. The description's `Skip when:
/simplify refines the current diff` clause is the routing half of this record.

## Presence

The bundled skill is gated by `disableBundledSkills`, a `skillOverrides` entry, the host surface,
and the environment. Tidy never invokes it and never chains into it; a session where it does not
resolve is an ordinary session.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, in which the skill
appears as a bundled skill. This record re-verifies the registration on the installed 2.1.263
binary by string search and reads the two pages named above, all on 2026-09-11.
