# The bundled `simplify` skill: pointer records

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row states the decision
this skill takes about the bundled surface, the upstream section to read for the current
behavior, the date it was checked, and the event that makes it worth checking again. The sibling
`batch-simplify` skill keeps its own record against the same surface in
[../../batch-simplify/context/bundled-simplify.md](../../batch-simplify/context/bundled-simplify.md).

| Decision | Pointer | As of | Recheck trigger |
|---|---|---|---|
| Treat `simplify` as a bundled skill invoked by its own name, never through an alias | The `/simplify` row in [All commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-11 | The row gains an alias or stops being labeled Skill |
| Treat `simplify` as a mutating surface that tidy never invokes or chains into | The same row | 2026-10-11 | The row documents a report-only mode or a flag that turns applying off |
| Route by anchor: `simplify` refines a diff that already exists; tidy hunts a lane regardless of recent changes | The same row, for the targets it takes; [Review a diff locally](https://code.claude.com/docs/en/code-review#review-a-diff-locally), for how it relates to `/code-review` | 2026-10-11 | Either section gives `simplify` a mode that hunts a scope independent of recent changes |
| Never assume presence; a session where it does not resolve is an ordinary session | [Bundled skills](https://code.claude.com/docs/en/skills#bundled-skills), for what turns bundled skills off | 2026-10-11 | That section changes the settings that turn a bundled skill off |

## Why the verdict is complementary

Both surfaces clean code without changing behavior. They differ in anchor: `/simplify` refines a
diff that exists, and tidy hunts unfiled drift across a glob-scoped lane regardless of recent
activity, under a scope budget, shipping one structure-only PR. The description's `Skip when:
/simplify refines the current diff` clause is the routing half of this record.

## Presence

Tidy never invokes the bundled skill and never chains into it; a session where it does not
resolve is an ordinary session.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, in which the skill
appears as a bundled skill. The pages named above are the live source for everything this record
decides.
