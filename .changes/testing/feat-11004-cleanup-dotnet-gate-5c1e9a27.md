---
bump: patch
---

### Fixed

- **`/testing:cleanup` finds a C# test's production files** ([#11004](https://github.com/melodic-software/claude-code-plugins/issues/11004)). The gate-blind check in step 5 and the candidate changes listed under `Gate: block` in step 6 used to read the production files a test file imports. A C# `using` names a namespace, not a file, so those checks had no answer on C#. Both now read the files defining the code a test reaches: what it calls directly, through a helper, an interface or dependency injection. When no changed test reaches a newly surviving mutant's file, `Gate: block` lists every changed test, since each mutant ran against the whole test set. Step 6 now says the replay compares the two records mutant by mutant, and the classifier brief hands over the production files each test reaches.
- A new `dotnet_gate_runs` eval runs the gated batch on the `cleanup-dotnet` fixture with `test-command: dotnet test {tests}`, and expects `Gate: pass` from the replay. The fixture gains its two `.csproj` files, a `.gitignore` for build output, and a `PriceFeedTests.cs.fixture` that calls `PriceFeed` directly. A `mutation-testing-dotnet.md` config beside it has the keys `/mutation-testing:setup apply` writes.
