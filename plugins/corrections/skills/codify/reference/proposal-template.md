# Proposal template

Every proposal section 6 writes or presents fills every section below, in this order. A section
that does not apply reads `none`, with the reason when it is not obvious; a section is never left
out. A mixed mistake repeats the sections from "Rung" to "Record line" once per part.

What some sections take:

- **Existing violations** and **Install** come from
  ["Next step per rung"](finding-classes.md#next-step-per-rung). `ratchet_offer` false leaves the
  ratchet offer out; the existing violations and any cleanup offer stay.
- **Adding the rule safely**: a checking rung states how the rule is added safely, and a rule to be
  written (a lint rule, an analyzer, a pattern rule) ships with its own valid and invalid rule
  tests and states what it does not catch, both per [adding-a-team-rule.md](adding-a-team-rule.md).
- **Record line**: a codebase, static-analysis or verification rung holds the literal `Codifies:`
  line for the pull request that lands it and, for work filed as an issue, the task-list item that
  carries it, per ["Record line"](finding-classes.md#record-line); a guidance or `human-review`
  rung holds neither.

```markdown
# Codify proposal: <one-line description>

## Problems
<a "no guardrail" finding, an unproven check, "no rung above holds it", or none>

## Description
<the described mistake, as data>

## Occurrences
<each occurrence with its commit hash and subject or its session message; the total next to the
threshold and the layer that set it, or the section 1 exception that let it through>

## Classification
<deterministic, detect-then-judge or reasoning-only for the whole mistake, or each part and its
tier when it mixes them>

## Rung
<the rung id for this part, the guardrail criterion items that decided it, and whether the rule
was loaded and ignored or never loaded>

## Rungs considered and rejected
<each stronger rung passed over, why it cannot hold this part, and its ## Next route>

## Scope
<team standard, project rule or user scope, and why; the existing rule this strengthens, or none>

## Check
<the one command, or none for a guidance or human rung; the line its message shows, naming the fix>

## Proof
<old ref, plant or fixture; both exit codes and the script's own lines; or none>

## Missing context
<what the model did not have in front of it, for a defect that escaped review; or none>

## Existing violations
<the count and how it was taken; the cleanup or ratchet offer, or none>

## Install
<the install step, whether it blocks, and the build hand-off: the rung, the check and the builder>

## Adding the rule safely
<how the rule lands safely, its rule tests and what it does not catch; or none>

## Instruction lines removed
<the instruction line a check replaces, removed in the same change, or none>

## Record line
<the literal Codifies: line and its task-list item; or none>
```
