# The three-way triage

Every comment in scope gets exactly one class, and every class has a treatment on **both** sides of
its test — a comment that fails class C's test is deleted, not kept for want of a branch. The
classes have **different tests** — class A is judged on information content, class B on
expressibility, class C on necessity — and conflating them applies the wrong treatment. The classic
failure is deleting a class-B comment as if it were class A: that destroys information the code was
supposed to absorb first.

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
ordering exists to prevent. Whether the refactor applies depends on its tier in
[safety.md](safety.md): a function-local rename applies behind the token proof even with no tests;
an additive move needs a discovered test net; an interface-creating move needs the net and is
proposed first. When the tier's gate does not pass, the item is **proposed**, and the comment stays
until the proposal lands.

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
   **Decide this on evidence, not impression.** Step 5 of the workflow runs
   `git log -L <start>,<end>:<file>` over the comment's own lines (or `git log -S` on a distinctive
   phrase) and checks the repo's ADR or decision-log directory where one is declared. A rationale a
   reader would find there **fails** this criterion; one absent from both, or whose commit trail
   restates only what the diff already shows, **passes**. History that cannot be read (shallow
   clone, unreadable blame) is recorded as unavailable and the comment is kept. Note the carve-out
   in the sentence above is about *constraints*, not rationale: a silent-breakage constraint is
   restated here even when history also carries it, and rationale gets no such exception.
3. **Within the line budget.** A kept comment is held to `class_c_max_lines` (default 2, from the
   plugin's user config). Over budget, the treatment is Henney's second verb, *rewritten*: keep
   the durable constraint in one or two lines, stage the narrative for the commit message
   ([safety.md](safety.md)), delete the rest. A genuinely load-bearing multi-line contract (a regex
   explanation, a concurrency invariant, a rejected-alternative record paired with a regression
   test) may exceed the budget when the report says why in one line **for that comment**, naming
   it by file and line. A single reason covering a category, a file, or a batch does not satisfy
   this and does not license the keeps under it: the per-comment sentence is the cost that keeps
   the exception rare. What never survives is length spent on justification narrative. Posture
   `balanced` reports an over-budget comment instead of rewriting it; `conservative` proposes the
   rewrite.

**When the test fails.** A comment that passes criterion 1 and fails criterion 2 is **deleted**
under `strict`, behind the same COMMENT-ONLY token proof class A uses, with its narrative staged
first per [safety.md](safety.md). It is not reclassified as class A — class A is redundancy with
code that is present, and this comment is not redundant — and it is not kept for want of a branch.
Criterion 3 has its own treatment, the rewrite above; only criterion 2 sends a comment to deletion.

Under `safe` mode and posture `conservative` this deletion is **proposed, never applied**. Those
modes apply class-A deletions only, and a comment that reached this branch is class C whatever its
test returned — the mode ladder narrows what is applied, and it does not get to be widened by a
verdict reached inside it.

A rewrite is an edit with a gate: the comment's replacement text is checked by
`change-shape.py` like any deletion (COMMENT-ONLY, since only comment tokens changed), and the
original wording is staged before the deletion is final. Prose quality of what remains can be
linted by Vale where a repository runs it (tree-sitter-backed, about 25 languages, none of Bash or
YAML); it is an optional lane, never a dependency.

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
| `// we retry twice here because the upstream 502s on cold start`, and the commit that added it says exactly that | C, criterion 2 fails | Stage the narrative, delete behind the COMMENT-ONLY proof (recoverable where a reader would look) |
| `// this is NOT thread-safe; callers serialize`, recorded nowhere else | C | Keep (negative information, load-bearing, terse — not exempt, but it passes the test) |
| 12-line comment explaining why approach X was chosen over Y | C, criterion 3 fails | Extract any durable constraint to one line; stage the narrative for the commit message; delete the rest |
