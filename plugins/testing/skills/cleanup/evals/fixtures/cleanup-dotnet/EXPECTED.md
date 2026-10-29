# Expected outcomes: C# cleanup fixture

What `/testing:cleanup Shop.Tests` must do over this fixture, in cannot-fail-only mode and, under
[Gated run](#gated-run), behind the mutation gate. The C# cleanup evals grade against this file.

## Setup per run

The fixture is committed on `main`; the run happens on a feature branch with a clean tree. The
fixture has no `.claude/mutation-testing.md`, so no mutation run is possible until the gated eval
adds one. In cannot-fail-only mode nothing is built or run: the mode runs no test.

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

## Gated run

The `dotnet_gate_runs` eval copies `../mutation-testing-dotnet.md` to `.claude/mutation-testing.md`
(`test-command: dotnet test {tests}`, `mutate: Shop/*.cs`) and
`Shop.Tests/PriceFeedTests.cs.fixture` to `Shop.Tests/PriceFeedTests.cs`, commits both on `main`,
and runs `/testing:cleanup Shop.Tests` with the `mutation-testing` plugin enabled. This run builds
and runs the tests.

- **Step 0** passes: `{tests}` is a standalone word, and every test file is C#.
- **Step 3** invokes `/mutation-testing:audit --exercised Shop.Tests --max 100 --record-mutants
  .work/testing-cleanup/shop.tests/before.tsv`. Each test-set run is `dotnet test` with one line
  of `dotnet-test-selection.sh`: `'Shop.Tests/Shop.Tests.csproj'` and a `--filter` naming
  `Shop.Tests.PriceFeedTests.` and `Shop.Tests.WiringTests.`. No run omits the project.
- **Mapping**: `PriceFeedTests` calls the `PriceFeed` constructor and `PriceOf` directly, so their
  bodies (`Shop/ServiceRegistration.cs:15-19`, `:21`) are mapped. `WiringTests` maps nothing: it
  reaches `AddShop` through the `BuildProvider` helper and `PriceOf` through `IPriceFeed`.
  `Rejects_options_without_a_url` kills the removal of the constructor's statement (lines 17-18),
  so K0 is not empty.
- **Production files**: `PriceFeedTests.cs` has no `using Shop;` (its namespace is a child of
  `Shop`), yet its production file is `Shop/ServiceRegistration.cs`, which holds `before.tsv` rows.
  A rewrite of `Feed_is_created` (`testing/audit/rule-throw-only-oracle`) is not gate-blind. The
  `WiringTests` tests reach the same file through `BuildProvider` and `IPriceFeed`.
- **Step 6** replays the `before.tsv` rows with `--replay-mutants` and `--record-mutants
  .work/testing-cleanup/shop.tests/after.tsv`, and `compare-records.sh` compares the two records
  mutant by mutant. No approval is given, so no deletion is applied. `Rejects_options_without_a_url`
  and `Prices_a_sku_by_its_length` have no finding and stay as they are, so every mutant detected
  before is detected again and the report reads `Gate: pass`. Nothing is committed.

The fixture's `.gitignore` keeps the `bin/` and `obj/` folders a build leaves out of
`git status`, so a resumed batch's step 0 check sees only the batch's own edits.
