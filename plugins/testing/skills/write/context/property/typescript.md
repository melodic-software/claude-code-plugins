# Property-based tests in TypeScript and JavaScript: fast-check

This page maps [../property.md](../property.md) onto fast-check. If the project uses a
different property library, apply the same page with that library's docs.

- **Declaring a property.** Inside a Jest or Vitest `it`/`test`, call
  `fc.assert(fc.property(arbA, arbB, (a, b) => ...))`. For promises use `fc.asyncProperty` and
  write `await fc.assert(...)`: an assert that is not awaited never reports its failure, which is
  the `rule-inert-assertion` shape `/testing:test-value` describes. The predicate fails the case by returning `false` or throwing. The audit's JavaScript adapter treats
  `fc.assert`, `fc.property` and `fc.asyncProperty` as property markers and skips the whole file
  for `rule-recomputed-derived`, so put example tests in another file.
- **Constraining inputs.** Arbitrary options carry the input rules:
  `fc.integer({ min: 0, max: 10_000_000 })` for an amount in cents, `fc.string({ minLength: 1, maxLength: 40 })`
  for a name, `fc.record({...})` for an object. For a value that depends on another, use `.chain`.
  `.filter` and `fc.pre` throw values away after generation; use them only when no option says the
  same thing.
- **Fixed inputs.** The `examples` option of `fc.assert` lists inputs to run before generated ones,
  which is where a past bug's input belongs.
- **Run size.** The `numRuns` option sets the case count for one call; `fc.configureGlobal` in the
  test setup file sets it for the suite, so CI can run more than a local watch.
- **Replay.** A failure prints a `seed` and a `path`. Passing both back to `fc.assert` reruns that
  exact case; copy the reduced input into an example test when you fix the bug.

Verification record. Claim: `fc.assert` takes a property and an optional parameters object whose
`numRuns`, `seed`, `path` and `examples` options set the run count, replay a failure, and add values
tried before generated ones. Basis: <https://fast-check.dev/docs/core-blocks/runners/> and
<https://fast-check.dev/docs/api/interfaces/Parameters/>. As of 2026-10-04. Recheck when a fast-check
major release renames those options or changes the runner signature.
