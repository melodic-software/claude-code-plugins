# Property-based tests in C#: FsCheck and CsCheck

This page maps [../property.md](../property.md) onto the two .NET libraries. Use
whichever one the project references already. The user chooses between them only if the project
has neither and they have approved adding one.

## FsCheck

- **Declaring a property.** Mark an xUnit test method `[Property]` (FsCheck.Xunit) and FsCheck
  supplies its parameters; a `Prop.ForAll(...)` expression works too. The audit's xUnit adapter
  treats both as property markers and skips the whole file for `rule-recomputed-derived`, so put
  example tests in another file.
- **Constraining inputs.** For a domain type such as an invoice, register an arbitrary that builds
  only valid invoices, so no test receives a raw primitive it has to reject.
- **Run size and replay.** On the attribute, `MaxTest` sets the case count and `Replay` takes the
  seed from a failure report; `[Properties]` on the class sets defaults for all its properties.

## CsCheck

- **Declaring a property.** Start from a generator and call `Sample`, for example
  `Gen.Int.Sample(i => ...)`; the lambda returns a `bool` or throws to fail. The audit's adapter
  recognizes `Gen.` calls as the CsCheck marker.
- **Constraining inputs.** Build domain generators with `Select` and LINQ query syntax, which also
  expresses one value depending on another; `Where` throws values away, so keep it rare.
- **Run size and replay.** `Sample` takes `iter` or `time` to bound the run and `seed` to rerun the
  case a failure message printed.

When the bug is fixed, copy the reduced input into a plain `[Fact]` or `[Test]`.

Verification record. Claim: FsCheck.Xunit's `PropertyAttribute` takes `MaxTest` and `Replay`, with
`PropertiesAttribute` for class-level defaults; CsCheck's `Sample` takes `iter`, `time` and `seed`,
and a failure prints the seed to replay. Basis: <https://fscheck.github.io/FsCheck/RunningTests.html>
and <https://github.com/AnthonyLloyd/CsCheck>. As of 2026-10-04. Recheck when either library ships a
major release that renames those parameters.
