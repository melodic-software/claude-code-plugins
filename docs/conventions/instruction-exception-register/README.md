# Instruction exception register — what a trimming pass may not delete

Owner doc for the classes of standing instruction that survive an instruction-audit trim on
consequence grounds, whatever a length, redundancy, or model-era check says about them.

The register exists because subtraction guidance has no natural floor. The current generation of
prompting guidance is explicitly subtractive: strip prescriptive scaffolding, let the model use
judgment, delete rules written for older models. That guidance is sound and this repo follows it,
but it is stated for behavioral rules and carries a carve-out its own wording leaves undefined,
"avoid making them overconstrained, **except in highly important areas**". Without a written
answer to which areas those are, a trimming pass has no principled stopping point.

## The classes are Gate 0's, adopted by reference

The consequence classes this register protects are exactly the six hard-deny classes in
[`plugins/instruction-placement/context/routing-rubric.md`](../../../plugins/instruction-placement/context/routing-rubric.md),
Gate 0: `irreversible-action`, `secret-handling`, `data-integrity`, `external-publication`,
`legal-compliance`, `agent-authority`.

**This document does not restate that table, and no other surface may fork it.** One concern keeps
one adjudication chain: the class list has a single owner, and a second enumeration under a second
name is the drift this repo has already paid for elsewhere.

What this register adds is the **operation**. Gate 0 governs *relocation*: whether a rule may be
demoted out of an always-loaded surface into a path-scoped or skill destination. Deletion is a
different operation with a strictly worse failure mode, because a demoted rule that fails to fire is
recoverable by re-promoting it while a deleted rule leaves nothing to re-promote. So:

> A candidate matching any Gate 0 class is **not deletable** by an instruction-audit trim. It may be
> compressed in place, given a rationale, or converted to a deterministic mechanism such as a hook.
> It is never removed on redundancy, brevity, or "the model already does this" grounds.

## Non-exhaustive, and tighten-only

Two properties are load-bearing and neither is decoration:

- **Non-exhaustive.** The classes are the recognized floor, never the complete set of things worth
  keeping. **Omission from this register is not licence to delete.** A rule outside every class is
  judged on its own merits by the auditing skill's normal criteria, exactly as it was before this
  document existed; it does not inherit a deletion warrant from its absence here.
- **Tighten-only.** A consuming repo or a downstream skill may add protected classes. Nothing that
  reads this register may use it to *weaken* a protection, and no argument, including an operator
  asking in the moment, removes a Gate 0 class from the protected set. That is Gate 0's own rule and
  it travels with the classes.

**Recognition is by consequence, not by phrasing**, also inherited from Gate 0. Ask what breaks when
the instruction is absent at the moment it was needed, not how the sentence is worded. A one-line
"never force-push a shared branch" is a protected rail; a paragraph preferring one git subcommand
over another is style.

## Who consumes this

| Consumer | How it uses the register |
|---|---|
| `claude-config:audit-instructions` | Deletion-class criteria (I1, I4, I5) hold back a candidate matching a protected class and report the hold rather than proposing the cut |
| `claude-config:unhobble` | The bare-baseline experiment may strip a protected rule during the run, since the strip is reversible and branch-local, but a protected rule is never left deleted on the evidence of "no stumble was observed" |
| `instruction-placement:*` | Unchanged. It owns the classes and the relocation verdict; this register is the deletion counterpart and defers to it on class membership |

A consumer that reads this register names it in its own criteria text. A register nothing consumes
changes no behavior, which is the failure mode this table exists to prevent.

## What this is not

- Not a second opinion on relocation. Gate 0 decides that, and a candidate held here may still be
  legitimately relocated.
- Not a suppression record. A finding an operator has judged and accepted is the
  [finding-suppression](../finding-suppression/README.md) convention's axis.
- Not a licence to keep everything. The subtractive posture stands for every candidate outside the
  protected classes, and compression in place remains the right answer for a protected rule that has
  genuinely grown bloated.

## Provenance

Adopted 2026-09-01 from the context-engineering corpus integration
([`docs/topics/context-engineering-integration/PLAN.md`](../../topics/context-engineering-integration/PLAN.md),
decision Q2). The carve-out this register answers is quoted from a vendor-voice source and carries
that source's status: the wording is first-party, the definition of "highly important areas" is
this repo's own and is not claimed to be upstream doctrine.
