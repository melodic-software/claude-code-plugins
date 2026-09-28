# Unhobble deletion-evidence attribution

Park for [#3563](https://github.com/melodic-software/claude-code-plugins/issues/3563).

## Decision

**Do not design or ship a per-rule deletion-evidence mode.** The shipped
grammar is the re-add gate: two rows, same cause, citing commits, after a
full strip. A deletion-direction copy would be a second mode even if it
reused the words. The issue asks for one grammar. Leaving the deletion tier
unclearable is the current validation record, and writing the design without
the wiring does not make the tier clearable.

**Claim:** Consequential standing-instruction deletions stay unclearable until
an operator funds a design that answers what a row is, over what window, and
attributed how, using the re-add grammar and no second one.
**Basis:** #3563 and `plugins/claude-config/skills/unhobble/SKILL.md` re-add
gate (the issue cites lines 159-176). `docs/topics/context-engineering-integration/PLAN.md`
Q1 is the signed-off decision that the deletion tier needs ledger evidence the
re-add gate does not supply. No origin/main file adds a deletion-evidence mode.
**As of:** 2026-09-28.
**Recheck:** An operator funds that design and the wiring that makes the
two-tier threshold clearable, still as one grammar.

## What this close is not

Not a new evidence grammar.
