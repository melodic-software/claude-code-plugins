# The bundled `batch` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each record below states our
reading in our own words and says where to read the specifics live.

## What `batch` is

`batch` is a bundled skill that researches and plans a large change, then runs it in parallel
across isolated worktree agents, each unit ending in its own PR. Its registration keeps it
person-invoked: the model does not start it. What it needs to run, how many units it splits into,
and its version floor are read live from the pointer, not restated here.

- **Probe:** the `/harness-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29
  (its description, argument hint, and invocability flags).
- **Pointer:** the `/batch` row of
  [commands: all commands](https://code.claude.com/docs/en/commands#all-commands), and
  [skills: bundled skills](https://code.claude.com/docs/en/skills#bundled-skills).
- **As of:** 2026-10-11.
- **Recheck trigger:** a release renames or removes `batch`, changes its invocability, or the
  `/batch` row changes what it needs to run.

## Turning it off

A consuming project can turn bundled skills off, or hide one, from its settings; which settings do
that is read live.

- **Pointer:** [skills: bundled skills](https://code.claude.com/docs/en/skills#bundled-skills) and
  [skills: override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings).
- **As of:** 2026-10-11.
- **Recheck trigger:** either section changes the setting that turns a bundled skill off or hides
  one.

## Why the verdict is complementary

`/batch` plans and executes in one run: it does its own research and decomposition, and the
units are independent by construction, each ending in its own PR. This skill starts where a plan
already exists and has been approved, runs phases in order with fences composed together per
wave, verifies every return against direct evidence, and gates each phase on a fresh-context
verifier. A large mechanical change with no plan is `/batch`'s case; a planned, ordered,
verified execution is this skill's.
