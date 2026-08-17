# The three-way triage

Every comment in scope gets exactly one class. The classes have **different tests** — class A is
judged on information content, class B on expressibility, class C on necessity — and conflating
them applies the wrong treatment. The classic failure is deleting a class-B comment as if it were
class A: that destroys information the code was supposed to absorb first.

## Class A — zero or negative information: delete outright

The comment adds nothing beyond the adjacent code, or is actively wrong.

- Restates what the line visibly does (`// increment counter` above `counter++`)
- Narrates the obvious flow of a block the reader can see
- Obsolete: describes behavior the code no longer has
- Commented-out code (version control owns history)

Deletion is the complete treatment — no refactor needed, no information lost. This class overlaps
`/code-tidying:audit-comment-residue`'s four residue shapes (history narration, plan references,
conversational antecedents, ticket back-references); when that skill has already produced findings,
its Tier 1 rows are class-A input here.

## Class B — real information the code could carry: refactor, then delete

The comment compensates for a naming or structure deficiency. The information is real; its
location is wrong. Treatment order is fixed: move the information into code via a
behavior-preserving refactoring (the named moves in
[dissolving-moves.md](dissolving-moves.md)), verify, and only then delete the comment —
Fowler's "first try to refactor the code so that any comment becomes superfluous."

Signals: the comment names what a block does (extract it), what a vague identifier means (rename
it), what a bare literal is (name the constant), what state must hold (assert it).

Deleting a class-B comment without the refactor is the information-destroying failure this
ordering exists to prevent. When the refactor cannot be applied (no test net, or the move would
change behavior), the item is **proposed**, and the comment stays until the proposal lands.

## Class C — information code cannot express: earn-its-keep, keep terse

A comment survives only if **all three** hold:

1. **Inexpressible** — the information cannot be carried by names, structure, types, or an
   assertion: why/rationale, a constraint from outside the code, a warning, a contract detail
   (units, invariants, side effects, boundary conditions), negative information ("this is NOT
   thread-safe").
2. **Load-bearing at the point of reading** — a future editor risks a bug or misuse without it,
   *at this location*. Rationale discoverable from context or version control does not need
   restating here; a constraint whose violation silently breaks something does, because blame
   trails are fragile across refactors.
3. **Terse — by default.** One to two lines is the posture, not a hard gate: a genuinely
   load-bearing multi-line contract (a regex explanation, a concurrency invariant) stays. What
   never survives is length spent on justification narrative.

**Justification routing.** Rationale defaults to routing out of code — commit message, PR
description, ADR — with a terse in-code why as the legitimate remainder. A lengthy why-comment is
treated as: extract the durable constraint into a one-liner (if there is one), stage the narrative
as a proposed commit-message block in the run's output, delete the rest. The staging happens
before the deletion is final — see [safety.md](safety.md).

## Doc comments

- **Public-API doc comments are exempt entirely** — docstrings, C# XML docs, JSDoc/TSDoc on
  exported surfaces. They feed documentation generators and IDE surfaces; deleting them is
  quasi-behavioral. Never touched, in any mode.
- **Private/internal doc comments** get the same three-way triage as any comment — a deliberate
  doctrine choice (the Martin pole for internal interfaces): a private method whose docstring
  restates its name and parameters is class A/B; one carrying a real contract is class C.

## Worked examples

| Comment | Class | Treatment |
|---|---|---|
| `// loop over users` above a `foreach` | A | Delete |
| `# TODO remove this later` (no issue) | A | Delete (a `TODO(#123)` is exempt) |
| `// check if the order qualifies for the discount` above 6 lines of conditions | B | Extract Function `QualifiesForDiscount(order)`, test, delete |
| `// 86400 = seconds per day` | B | Replace Magic Literal `SecondsPerDay`, delete |
| `// items must stay sorted; binary search below depends on it` | C | Keep (constraint, load-bearing, terse) |
| 12-line comment explaining why approach X was chosen over Y | C-adjacent narrative | Extract any durable constraint to one line; stage the narrative for the commit message; delete the rest |
