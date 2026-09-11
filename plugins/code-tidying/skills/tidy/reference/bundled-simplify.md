# The bundled `simplify` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The sibling `batch-simplify` skill keeps its own record against the same
surface in [../../batch-simplify/context/bundled-simplify.md](../../batch-simplify/context/bundled-simplify.md).

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `simplify` ships with Claude Code as a bundled skill, alias `/readable`: "Simplify the current diff for readability, or a PR number, branch, or path you pass. Pass `--fix` to apply findings", with an effort level argument | The `/simplify` row on <https://code.claude.com/docs/en/commands>, labeled Skill | 2026-09-11 | The row changes its targets, flags, or alias, or the page it links (`/docs/en/simplify`, which returned 404 on 2026-09-11) resolves |
| Its registered description reads "Review the changed code for reuse, simplification, efficiency, and altitude cleanups, then apply the fixes. Quality only, it does not hunt for bugs; use /code-review for that", menu line "Clean up the changed code without changing behavior" | String search of the installed 2.1.263 binary | 2026-09-11 | A release changes the registration text |
| It mutates. The binary's prompt says "then apply the fixes"; the commands row says fixes apply when `--fix` is passed. The two sources disagree on the default, so treat every run as one that may edit the working tree | The two rows above | 2026-09-11 | Either source states the default unambiguously |
| It is diff-anchored: the target is the current diff, a PR, a branch, or a path, always something that already changed | The commands row; the code-review page: "`/simplify` runs a separate cleanup-only review that applies fixes without hunting for bugs" (<https://code.claude.com/docs/en/code-review>) | 2026-09-11 | The skill gains a mode that hunts a scope independent of recent changes |

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
