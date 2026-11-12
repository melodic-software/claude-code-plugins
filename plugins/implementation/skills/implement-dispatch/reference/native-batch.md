# The bundled `batch` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each record below states our
reading in our own words and says where to read the specifics live.

## What `batch` is

`batch` is a bundled skill that researches and plans a large change, then runs it in parallel
across isolated worktree agents. Its registration keeps it person-invoked: the model does not
start it. How each unit ends, what it needs to run, how many units it splits into, and its version
floor are read live from the pointer, not restated here.

- **Probe:** the `/harness-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29
  (its description, argument hint, and invocability flags).
- **Pointer:** the `/batch` row of
  [commands: all commands](https://code.claude.com/docs/en/commands#all-commands), and
  [skills: bundled skills](https://code.claude.com/docs/en/skills#bundled-skills).

## Turning it off

A consuming project can turn bundled skills off, or hide one, from its settings; which settings do
that is read live.

- **Pointer:** [skills: bundled skills](https://code.claude.com/docs/en/skills#bundled-skills) and
  [skills: override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings).

## Why the verdict is complementary

`/batch` plans and executes in one run: it does its own research and decomposition, and the
units are independent by construction. This skill starts where a plan already exists and has been
approved, runs phases in order with fences composed together per wave, verifies every return
against direct evidence, and gates each phase on a fresh-context verifier. A large mechanical change with no plan is `/batch`'s case; a planned, ordered,
verified execution is this skill's.
