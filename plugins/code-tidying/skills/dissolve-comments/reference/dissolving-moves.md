# Dissolving moves — comment shape → named refactoring

All names are Fowler-catalog names (refactoring.com/catalog), verified current at authoring time.
The first three rows are Fowler's own prescription in the Comments smell entry; the rest apply the
same logic with catalog names. Every move is behavior-preserving in Fowler's sense and inherits
the test-net presumption — see [safety.md](safety.md).

| Comment shape being dissolved | Named refactoring |
|---|---|
| Block comment narrating what a section does | **Extract Function** |
| Comment compensating for a vague function name | **Change Function Declaration** (rename) |
| Comment stating a required state / precondition / invariant | **Introduce Assertion** |
| Comment explaining a complex expression | **Extract Variable** (alias: Introduce Explaining Variable) |
| Comment explaining what a variable/field holds | **Rename Variable** / **Rename Field** |
| Comment explaining a bare literal | **Replace Magic Literal** |
| Comment walking through a complicated conditional | **Decompose Conditional** |
| Comment explaining special-case handling up front | **Replace Nested Conditional with Guard Clauses**; **Introduce Special Case** |
| Section-marker comments segmenting a long function | **Extract Function**; **Move Statements into Function** |
| Comment explaining duplicated inline logic | **Replace Inline Code with Function Call** |
| Comment explaining a clump of parameters | **Introduce Parameter Object** |
| Over-extracted fragment whose name now needs a comment | **Inline Function** (the reverse move) |

## Cautions

- **Extraction has a cost curve.** Each extraction adds an interface. A name that must grow
  megasyllabic to stay honest (`isLeastRelevantMultipleOfLargerPrimeFactor`) signals the
  information did not fit the name channel — short name + terse class-C comment, or Inline
  Function, is the correct move, not a longer name.
- **Names cannot carry why.** Every move above targets *what*-information. Rationale, warnings,
  contract units, and negative information are class-C keeps — no refactoring dissolves them.
- **Assertions replace only checkable claims.** Introduce Assertion covers machine-checkable
  state; a comment stating an unverifiable assumption (about an external system, an operational
  constraint) stays a comment.
- **Renames have blast radius.** Change Function Declaration / Rename on anything referenced
  outside the run's scope needs every call site updated in the same pass; if references cannot be
  fully resolved (dynamic dispatch, reflection, string-based lookup), demote to a proposal.
