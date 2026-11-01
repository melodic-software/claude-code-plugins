---
bump: patch
---

### Fixed

- `/testing:audit` now claims a C# file that holds a test attribute (`[Fact]`, `[Theory]`, `[Test]`, `[TestCase]` or a `TestMethod`), even when its name matches none of the C# adapters' name patterns, so files like `DiscountSpecs.cs` and `CalculatorTestsExtra.cs` are scanned. `/testing:cleanup` on such a folder now gets past its file-claim check. Adapters can declare this with the new `claim_by_content` field, which takes `files` globs and `any_regex` patterns ([#11816](https://github.com/melodic-software/claude-code-plugins/issues/11816)).
