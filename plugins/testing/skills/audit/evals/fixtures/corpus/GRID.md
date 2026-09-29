# Corpus coverage grid

One row per adapter in `adapters/`, one column per deterministic rule. A `pair` cell needs a bad
file in `<adapter>/bad/` carrying `expect: <rule>` and a good file in `<adapter>/good/` carrying
`good-for: <rule>`. Any other cell reads `n/a: <reason>`. `scripts/check-corpus-grid.sh` enforces
both for this first table only.

| Adapter | rule-zero-assertion | rule-recomputed-expectation | rule-inert-assertion | rule-constant-restatement | rule-source-text-read | rule-conditional-assertion | rule-recomputed-derived | rule-snapshot-only | rule-weak-oracle |
|---|---|---|---|---|---|---|---|---|---|
| bash-bats | pair | pair | pair | pair | pair | n/a: bats if and for close with fi and done, which the engine does not track | n/a: partial, an expected value from a command substitution hides its provenance | n/a: partial, a golden file hides whether it was reviewed | n/a: a bats check is a command whose exit status is the whole oracle, with no weak-matcher vocabulary |
| bash-harness | pair | pair | pair | pair | pair | n/a: the whole file is one block, and if and for close with fi and done | n/a: partial, an expected value from a command substitution hides its provenance | n/a: partial, a golden file hides whether it was reviewed | n/a: a harness check is a command whose exit status is the whole oracle, with no weak-matcher vocabulary |
| cs-mstest | pair | pair | pair | n/a: needs a declaration lookup (C# constants are PascalCase) | pair | pair | pair | pair | pair |
| cs-nunit | pair | pair | pair | n/a: needs a declaration lookup (C# constants are PascalCase) | pair | pair | pair | pair | pair |
| cs-xunit | pair | pair | pair | n/a: needs a declaration lookup (C# constants are PascalCase) | pair | pair | pair | pair | pair |
| go-testing | pair | pair | pair | n/a: needs a declaration lookup (Go constants are CamelCase) | pair | pair | pair | pair | pair |
| js-jest | pair | pair | pair | pair | pair | pair | pair | pair | pair |
| js-node-test | pair | pair | pair | pair | pair | pair | pair | pair | pair |
| js-playwright | pair | pair | pair | pair | pair | pair | n/a: exempt, expected values come from seed data checked in another process | pair | pair |
| js-vitest | pair | pair | pair | pair | pair | pair | pair | pair | pair |
| pwsh-pester | pair | pair | pair | n/a: needs a declaration lookup (PowerShell has no uppercase constant convention) | pair | pair | pair | n/a: partial, a golden file read with Get-Content hides whether it was reviewed | pair |
| py-pytest | pair | pair | pair | pair | pair | pair | pair | pair | pair |
| py-unittest | pair | pair | pair | pair | pair | pair | pair | pair | pair |

## Pocock examples

Each Pocock example from `.work/tautological-tests/phase4-pocock-examples.md` names its rule, or
`judge` when only reasoning can catch it. A judge row is a Release 2 judge calibration candidate
and has no corpus file.

| Id | Source | Rule or judge | Phase | Fixture |
|---|---|---|---|---|
| T1 | talk | rule-constant-restatement | 4a | `js-vitest/bad/vitest-post-limit-restated.test.ts.fixture` |
| T2 | talk | rule-source-text-read | 4a | `js-vitest/bad/vitest-pitch-detail-source-order.test.ts.fixture` |
| T3 | talk | judge: Release 2 judge calibration candidate | Release 2 | none |
| M1 | tests.md | rule-mock-only-oracle | 4a | `js-jest/bad/jest-checkout-calls-payment-verbatim.test.ts.fixture` (verbatim, invalid Jest), `js-jest/bad/jest-checkout-calls-payment.test.ts.fixture` (corrected) |
| M2 | tests.md | judge: Release 2 judge calibration candidate | Release 2 | none |
| M3 | tests.md | judge: Release 2 judge calibration candidate | Release 2 | none |
| M4 | tests.md | rule-mock-only-oracle | 4a | `js-jest/bad/jest-sync-call-count.test.ts.fixture` |
| M5 | tests.md | judge: Release 2 judge calibration candidate | Release 2 | none |
| M6 | tests.md | judge: Release 2 judge calibration candidate | Release 2 | none |
| M7-weak | tests.md | rule-weak-oracle | 4b | `js-jest/bad/jest-create-user-defined-verbatim.test.ts.fixture` (verbatim) |
| M7-side-channel | tests.md | judge: Release 2 judge calibration candidate | Release 2 | none |
| M8 | tests.md | rule-recomputed-derived | 4b | `js-vitest/bad/vitest-order-total-recomputed.test.ts.fixture` (verbatim, vitest import added) |
| S2 | SKILL.md | rule-recomputed-derived | 4b | `js-vitest/bad/vitest-add-recomputed.test.ts.fixture` |
| S3 | SKILL.md | judge: Release 2 judge calibration candidate | Release 2 | none |
| S4 | SKILL.md | rule-recomputed-expectation | 4a | `js-vitest/bad/vitest-limit-against-itself.test.ts.fixture` |
| S5 | SKILL.md | judge: Release 2 judge calibration candidate | Release 2 | none |

## Planted

The twelve planted tests from `.work/tautological-tests-verify/taxonomy/fx/`, one per file under
`planted/bad/`, each naming its adapter in an `adapter:` header. The taxonomy marks none of the
twelve as needing reasoning.

| File | Test | Rule | Phase |
|---|---|---|---|
| `planted-constant-restatement.test.ts` | constant restatement | rule-constant-restatement | 4a |
| `planted-reduce-recomputed.test.ts` | reduce recomputed | rule-recomputed-derived | 4b |
| `planted-unawaited-expect.spec.ts` | unawaited expect | rule-inert-assertion | 4a |
| `planted-source-text.test.ts` | source text | rule-source-text-read | 4a |
| `planted-self-identity.test.ts` | self identity control | rule-recomputed-expectation | existing |
| `planted-no-assertion.test.ts` | no assertion control | rule-zero-assertion | existing |
| `test_planted_tuple_assert.py` | test_tuple_assert | rule-inert-assertion | 4a |
| `test_planted_sum_recomputed.py` | test_sum_recomputed | rule-recomputed-derived | 4b |
| `test_planted_constant.py` | test_constant | rule-constant-restatement | 4a |
| `PlantedSumRecomputedTests.cs` | SumRecomputed | rule-recomputed-derived | 4b |
| `PlantedShouldAloneTests.cs` | ShouldAlone | rule-inert-assertion | 4a |
| `PlantedUnawaitedAsyncTests.cs` | UnawaitedAsync | rule-inert-assertion | 4a |
