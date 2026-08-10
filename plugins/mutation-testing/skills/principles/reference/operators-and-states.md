# Mutants: states and operators

What a mutant is, what happens to it, and the catalogs of faults tools know how to inject.

Sources: [Stryker — mutant states and
metrics](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/);
[PIT mutation operators](https://pitest.org/quickstart/mutators/); Petrović & Ivanković, *State of
Mutation Testing at Google* (ICSE-SEIP 2018) and Petrović, Ivanković, Fraser & Just, *Practical
Mutation Testing at Scale* (<https://arxiv.org/abs/2102.11378>). Fetched 2026-08-10.

## The mutant lifecycle

1. Pick a location in the code under test.
2. Apply one operator — a single small, syntactically valid change.
3. Run the tests that cover that location.
4. Record the outcome.
5. **Revert.** The source is unchanged when the run ends. A mutation run is net-zero on the working
   tree; anything that leaves a mutation behind is a bug in the harness, not a finding.

## States

Stryker's vocabulary is the one the other tools converge on:

| State | Meaning | Counts as |
|---|---|---|
| **Killed** | At least one test failed while this mutant was active | Detected |
| **Survived** | All tests passed while this mutant was active | Undetected |
| **No coverage** | No test covers the mutant, so it survived by default | Undetected |
| **Timeout** | Running the tests with the mutant active timed out (typically an infinite loop) | Detected |
| **Runtime error** | The run errored rather than failing a test | Invalid |
| **Compile error** | The mutant did not compile (compiled languages only) | Invalid |
| **Ignored** | Deliberately not tested — user configuration or another documented reason | Excluded |
| **Pending** | Generated, not yet run | Excluded |

Two of these routinely mislead:

- **Timeout counts as detected.** An infinite loop *is* a detected behavior change. Do not read
  timeouts as failures of the harness by default — but a suite whose score leans heavily on timeouts
  is worth a look, because it is being carried by wall-clock rather than assertions.
- **No coverage is not a weak test.** It is an absent test. Keeping it in the same bucket as
  "survived" is what makes the plain mutation score misleading; see
  [metrics.md](metrics.md).

## Operator catalogs

An operator is a rule for producing one mutant. Tools ship fixed catalogs — the mutants are not
invented per run, which is what makes the technique reproducible.

### PIT's default set (Java/JVM)

| Operator | What it does |
|---|---|
| Conditionals boundary | `<` → `<=`, `>` → `>=` and their counterparts |
| Negate conditionals | `==` → `!=`, `<` → `>=`, and so on |
| Math | Swaps a binary arithmetic operation for another (`+ - * / % & \| ^ << >> >>>`) |
| Increments | Swaps a local-variable increment for a decrement |
| Invert negatives | Removes negation from a numeric value |
| Void method calls | Deletes a call to a void method |
| Empty returns | Returns a type-appropriate empty value (empty string, empty collection, zero) |
| False returns / True returns | Forces a boolean return |
| Null returns | Returns `null` for an object return |
| Primitive returns | Returns `0` for a numeric return |

Optional and experimental sets go further — constructor calls to `null`, remove-conditionals (force
a branch always taken), remove-increments, non-void method call replacement, argument propagation,
switch mutation, bitwise operators. Turning these on raises both the mutant count and the
unproductive rate; start with defaults.

### Google's five (multi-language, at scale)

Narrowed deliberately, and worth knowing because the narrowing is the finding:

| Operator | What it does |
|---|---|
| **AOR** | Arithmetic operator replacement — `a + b` → `a`, `b`, `a - b`, `a * b`, … |
| **LCR** | Logical connector replacement — `a && b` → `a`, `b`, `a \|\| b`, … |
| **ROR** | Relational operator replacement — `a > b` → `a < b`, `a <= b`, … |
| **SBR** | Statement block removal — `stmt` → nothing |
| **UOI** | Unary operator insertion — `a` → `a++`, `a--` |

**SBR dominates**, accounting for roughly 68% of generated mutants in their corpus. That matters for
any language without an off-the-shelf tool: deleting a statement or a block is the single
highest-yield operator, it is trivial to apply to any language, and it is exactly the operator used
by hand in this repository's own `lib/hook-utils.test.sh` mutation notes.

## Choosing operators when there is no tool

For a language with no mutation tooling, a hand-rolled or agent-driven pass should start with the
two operators that need no parser:

1. **SBR** — delete one statement or one block.
2. **ROR / negate-conditionals** — invert one comparison.

Both are language-agnostic, both produce a syntactically valid program in most languages, and
together they cover the two failure modes that assertions most often miss: a step that never ran,
and a guard that never fired. See [tooling.md](tooling.md) for when this is and is not appropriate.
