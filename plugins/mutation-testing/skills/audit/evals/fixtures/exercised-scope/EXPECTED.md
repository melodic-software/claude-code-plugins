# Expected outcomes: exercised-scope fixture

What `/mutation-testing:audit --exercised` must report for each scenario. The audit evals and the
live runs grade against this file.

## Setup per run

`app.py` and `.claude/mutation-testing.md` are committed on `main`; one scenario's `test_app.py` is
added on a branch (committed, or left uncommitted for `no_assertion_uncommitted`). The changed-test
set is that one file. The `testing` plugin's `py-unittest` or `py-pytest` adapter claims it.

## Mapping

Every scenario calls `price_with_tax`, so the mapped-line set is its body, `app.py` lines 7-10.
The module constants (lines 1-3) are not in a function body the tests call.

## Mutants

The manual protocol, one mutant per mapped line. Lines 8-10 take statement removal. Line 7 is an
`if` header: removing the block would also remove line 8, which has its own mutant, so it takes the
second operator, a relational boundary shift.

| Mutant | Line | Operator | Mutation |
|---|---|---|---|
| M1 | 7 | relational boundary | `amount > DISCOUNT_THRESHOLD` to `amount >= DISCOUNT_THRESHOLD` |
| M2 | 8 | statement removal | `amount = amount * (1 - DISCOUNT_RATE)` to `pass` |
| M3 | 9 | statement removal | `amount = amount * (1 + TAX_RATE)` to `pass` |
| M4 | 10 | statement removal | `return round(amount, 2)` to `pass` |

Each state below was measured by applying the mutant and running the scenario's test with
`python3 -m unittest`.

## Scenario `no_assertion`

The test calls `price_with_tax(150)` and asserts nothing.

| Mutant | State | Disposition | Cause |
|---|---|---|---|
| M1 | survived | productive | no-assertion |
| M2 | survived | productive | no-assertion |
| M3 | survived | productive | no-assertion |
| M4 | survived | productive | no-assertion |

The same outcome holds for `no_assertion_uncommitted`: the uncommitted test is still in the
changed-test set.

## Scenario `boundary`

The test asserts `price_with_tax(1000) == 1080.0`, a hand-computed literal (1000 less 10% is 900,
plus 20% tax is 1080).

| Mutant | State | Disposition | Cause |
|---|---|---|---|
| M1 | survived | productive | input-gap |
| M2 | killed | | |
| M3 | killed | | |
| M4 | killed | | |

M1 lives because no input sits at the threshold (100), where `>` and `>=` differ. A run that
inverts line 7 to `<=` instead of shifting the boundary kills M1 at 1000, and this scenario then has
no survivor; the shift is the mutant this fixture expects.

## Scenario `calls_sut`

The test asserts `price_with_tax(150) == price_with_tax(150)`: the expected value comes from the
code under test.

| Mutant | State | Disposition | Cause |
|---|---|---|---|
| M1 | survived | productive | unclassified |
| M2 | survived | productive | unclassified |
| M3 | survived | productive | unclassified |
| M4 | survived | productive | unclassified |

The test has an assertion, so a triage without the tie-break could call these `input-gap`. The
expected side calls the mutated function, so each is `unclassified` and names the judge rule
`testing/judge/rule-restated-expectation`. None is `input-gap`.

## Every report

- The scope line reads `Scope: exercised, changed tests as one set` (or `tests under <test-path>`
  as one set when a test path is passed).
- Coverage and gap print `unknown`: the manual protocol records no no-coverage state.
- The blind-spot line names `testing/judge/rule-restated-expectation`.
