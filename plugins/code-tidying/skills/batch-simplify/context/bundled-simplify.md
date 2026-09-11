# The bundled `simplify` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The sibling `tidy` skill keeps its own record against the same surface in
[../../tidy/reference/bundled-simplify.md](../../tidy/reference/bundled-simplify.md).

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `simplify` ships with Claude Code as a bundled skill, alias `/readable`: "Simplify the current diff for readability, or a PR number, branch, or path you pass. Pass `--fix` to apply findings", with an effort level argument | The `/simplify` row on <https://code.claude.com/docs/en/commands>, labeled Skill | 2026-09-11 | The row changes its targets, flags, or alias, or the page it links (`/docs/en/simplify`, which returned 404 on 2026-09-11) resolves |
| Its registered description reads "Review the changed code for reuse, simplification, efficiency, and altitude cleanups, then apply the fixes. Quality only, it does not hunt for bugs; use /code-review for that" | String search of the installed 2.1.263 binary | 2026-09-11 | A release changes the registration text |
| It mutates. The binary's prompt says "then apply the fixes"; the commands row says fixes apply when `--fix` is passed. Treat every run as one that may edit the working tree | The two rows above | 2026-09-11 | Either source states the default unambiguously |
| One run takes one target. The target may already span many files (a PR, a branch, or a directory path), so the registry row's trigger, "a multi-file argument form", is half fired; no time-window form exists | The commands row | 2026-09-11 | The skill gains a time-window argument, a repository mode, or ecosystem grouping |

## Why the verdict is complementary

Same cleanup job, different scale and discipline. `/simplify` is one pass over one target and
applies its fixes; batch-simplify sweeps a time window, a branch, or the whole repository in
waves, grouped by ecosystem in dependency order, with a checklist, a deferred-items contract, and
docs-mode factual staleness that the bundled skill does not cover. The description's `Skip for
single-file cleanup, use /simplify instead` clause is the routing half of this record.

## Presence

The bundled skill is gated by `disableBundledSkills`, a `skillOverrides` entry, the host surface,
and the environment. Batch-simplify runs its own passes and never chains into the bundled skill;
a session where it does not resolve is an ordinary session.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, in which the skill
appears as a bundled skill. This record re-verifies the registration on the installed 2.1.263
binary by string search and reads the commands page, both on 2026-09-11.
