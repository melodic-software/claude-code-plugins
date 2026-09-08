# Dissolving moves — comment shape → named refactoring

All names are Fowler-catalog names. Basis: <https://refactoring.com/catalog/>, read 2026-08-17.
Recheck trigger: a move name in the table below failing to resolve on that page.
The first three rows are Fowler's own prescription in the Comments smell entry; the rest apply the
same logic with catalog names. Every move is behavior-preserving in Fowler's sense, but they do
not share one proof of it: each sits in a tier of [safety.md](safety.md) that names the strongest
available certification. Renames are proven by token comparison; additive local moves need a test
net; interface-creating moves need a test net and stay proposals in non-interactive runs.

| Tier | Moves |
|---|---|
| 1, token-proven | Rename Variable, Rename Field (function-local identifiers only) |
| 2, test-gated | Extract Variable, Replace Magic Literal, Introduce Assertion, Slide Statements, Decompose Conditional, Replace Nested Conditional with Guard Clauses, Introduce Special Case |
| 3, test-gated and proposal-first | Extract Function, Change Function Declaration, Move Statements into Function, Replace Inline Code with Function Call, Introduce Parameter Object, Inline Function |

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

## Apply capacity — what class B can actually change on a given repository

Class B reads like the skill's main engine. On many repositories it turns over nothing, and a run
planned around it should know the three limits up front. All three are deliberate.

- **2 of the 15 moves need no test net.** Only Rename Variable and Rename Field are tier 1, and
  only on a *function-local* identifier. Every other move adds tokens, so the token proof reports
  CODE-CHANGED by construction ([safety.md](safety.md)) and a discovered test net is required;
  without one they are proposed, never applied.
- **0 of 15 apply with tree-sitter absent.** The proof is unavailable, so "tier 1 without its proof
  is tier 2" ([safety.md](safety.md)) demotes the two renames into the test-net tier with
  everything else. On a repository with neither a runnable test net nor tree-sitter, a class-B pass
  produces a proposal list and no edits.
- **No move dissolves a why.** Names carry what and how, not why — the cost curve above says a name
  that grows to carry rationale is a dishonest name. Rationale therefore never leaves through
  class B; it is decided by the class-C earn-its-keep test, which `SKILL.md` step 5 evaluates on
  evidence.

The consequence worth stating plainly: on a rationale-dense codebase a class-B count of zero is the
expected result, not a sign the pass failed to look.
