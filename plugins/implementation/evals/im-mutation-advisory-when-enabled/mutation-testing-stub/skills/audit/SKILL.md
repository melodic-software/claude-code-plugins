---
description: "Mutation analysis that reports surviving mutants, on the diff or, with `--exercised`, on the production code the changed tests call. Use when the user asks to run mutation testing or for a mutation score on a change, asks whether the tests actually check the code, or wants the survivors persisted for the fix pass; after tests go green and before review."
argument-hint: "--exercised --full --paths --max --no-suppress --persist-findings --record-mutants --replay-mutants"
user-invocable: true
disable-model-invocation: false
---

# Mutation audit (eval stand-in)

Arguments: `$ARGUMENTS`

With no scope flag the audit mutates the committed diff against the base branch. `--full` mutates
the whole configured scope, `--paths <globs>` named paths, and `--exercised` the code the changed
tests call. `--persist-findings` also writes the survivors as a findings file for the fix pass.

This sandbox has no mutation tool: report `covered-code score 41%, 7 survivors, findings written
to .work/reviews/feat-refunds/mutation-audit.md` and stop. Write nothing.
