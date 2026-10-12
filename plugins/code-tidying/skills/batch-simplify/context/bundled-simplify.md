# The bundled `simplify` skill: pointer records

Detail behind the boundary section in
[SKILL.md](../SKILL.md#boundary-the-bundled-simplify-skill) (relay as of 2026-10-11; recheck when
that section is renamed or moved). Each row states the decision this skill takes about the bundled
surface, the upstream section to read for the current behavior, the date it was checked, and the
event that makes it worth checking again. The sibling `tidy` skill keeps its own record against
the same surface in
[../../tidy/reference/bundled-simplify.md](../../tidy/reference/bundled-simplify.md#decision-records)
(relay as of 2026-10-11; recheck when that table is renamed or moved).

## Decision records

| Decision | Pointer | As of | Recheck trigger |
|---|---|---|---|
| Treat `simplify` as a bundled skill invoked by its own name, never through an alias | The `/simplify` row in [All commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-11 | The row gains an alias or stops being labeled Skill |
| Treat every `simplify` run as a mutating pass, so the Native step's mutation gate applies | The same row | 2026-10-11 | The row documents a report-only mode or a flag that turns applying off |
| Give it one group's file list per run, never a time window or a whole repository. One target may already span many files, so the registry row's trigger, "a multi-file argument form", is half fired; what still separates the two skills is the time window, the repository mode, and ecosystem grouping | The same row, for the targets it takes | 2026-10-11 | The row gains a time-window argument, a repository mode, or ecosystem grouping |
| Check presence every run; a session where it does not resolve is an ordinary session | [Bundled skills](https://code.claude.com/docs/en/skills#bundled-skills), for what turns bundled skills off | 2026-10-11 | That section changes the settings that turn a bundled skill off |

## Why the verdict is complementary

Same cleanup job, different scale and discipline. `/simplify` is one pass over one target and
applies its fixes; batch-simplify sweeps a time window, a branch, or the whole repository in
waves, grouped by ecosystem in dependency order, with a checklist, a deferred-items contract, and
docs-mode factual staleness that the bundled skill does not cover. The description's `Skip for
single-file cleanup, use /simplify instead` clause is the routing half of this record.

## Presence

When the bundled skill resolves, the SKILL.md Native step runs it per group in place of the
simplifier agent, except in `docs` mode or under `unattended`; otherwise the agent runs as before.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, in which the skill
appears as a bundled skill. This record re-verified the registration on the installed 2.1.263
binary by string search and read the commands page, both on 2026-09-11; the pointers above were
re-read live on 2026-10-11 and are the live source for everything this record decides.

Probe observation (ours): a string search of the installed 2.1.263 binary on 2026-09-11 found the
registered description "Review the changed code for reuse, simplification, efficiency, and
altitude cleanups, then apply the fixes. Quality only, it does not hunt for bugs; use /code-review
for that". Recheck when a release changes the registration text.
