# Expected outcomes: cannot-fail-only fixture

What `/testing:cleanup Shop.Tests --cannot-fail-only` must do over this fixture. The
cannot-fail-only evals grade against this file.

## Setup per run

The fixture is committed on `main`; the run happens on a feature branch with a clean tree. The
fixture has no `.claude/mutation-testing.md`, so no mutation run is possible. Nothing here is built
or run: the mode runs no test.

## Scanner findings (mode step 1)

| Location | Rule | Candidate |
|---|---|---|
| `Shop.Tests/WiringTests.cs:16` (`Price_feed_resolves`) | `testing/audit/rule-zero-assertion` | yes |
| `Shop.Tests/WiringTests.cs:25` (`Wiring_is_sane`) | `testing/audit/rule-inert-assertion` (report-only) | yes |
| `Shop.Tests/WiringTests.cs:31` (`Price_feed_type_exists`) | `testing/audit/rule-inert-assertion` (report-only) | yes |
| `Shop.Tests/WiringTests.cs:39` (`Price_feed_is_not_null`) | `testing/audit/rule-weak-oracle` (report-only) | no: `not in this mode` |
| `Shop.Tests/WiringTests.cs:46` (`Price_feed_prices_two_letter_sku`) | `testing/audit/rule-inert-assertion` (report-only) | no: its `Assert.Equal(2m, ...)` on line 47 is an assertion outside the in-scope rows, so the test is `not in this mode` |

`Licensed_feed_prices_a_sku` has no finding. Its `catch (InvalidOperationException ex) when
(IsTrialFailure(ex))` guard is never flagged, deleted or edited.

## Decisions (mode steps 2-4)

| Test | Skeptic | Action |
|---|---|---|
| `Price_feed_resolves` | `can-fail`: `provider.GetRequiredService<IPriceFeed>()` resolves `PriceFeed`, whose constructor throws when `PriceFeedUrl` is unset (`Shop/ServiceRegistration.cs:17-18`), and throws when the `AddShop` registration is missing | `keep: throw is the only oracle (Shop.Tests/WiringTests.cs:19)`; never a deletion |
| `Wiring_is_sane` | `cleared`: `Assert.True(true)` is its only statement and cannot fail; the class has no constructor or fixture | deletion proposed, applied only on the user's yes |
| `Price_feed_type_exists` | `cleared`: `typeof(IPriceFeed)` is a compile-time constant and never null, and `IPriceFeed` stays named by the other tests (`Shop.Tests/WiringTests.cs:19`), so no compile-time check is lost | deletion proposed, applied only on the user's yes |

No rewrite, merge or quarantine is proposed. `Price_feed_is_not_null` is weak but can fail, so it is
listed as `not in this mode` and left as it is. So is `Price_feed_prices_two_letter_sku`: its inert
`Assert.True(true)` is flagged, but its `Assert.Equal` can fail, so the whole test is never a
deletion candidate.

## Check (mode step 5)

Step 1's scan parses 6 test blocks. With both deletions approved, the re-scan parses 4, and
`git status --porcelain` lists only `Shop.Tests/WiringTests.cs`. The `BuildProvider` and
`IsTrialFailure` helpers stay. The report says nothing was built or linted and asks the user to
build the test project. Nothing is committed before the user approves the batch.
