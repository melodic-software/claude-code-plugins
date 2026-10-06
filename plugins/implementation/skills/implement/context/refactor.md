# Refactor Implementation

Refactoring changes structure without changing behavior. Key discipline: **structural commits and behavioral commits are never mixed.**

## The Tidy First Principle

Kent Beck's "Tidy First?" principle: make the change easy, then make the easy change.

- **Tidy (structural)**: rename, extract method/class, move file, reorganize namespace, simplify conditionals
- **Change (behavioral)**: new feature, bug fix, performance improvement

These go in separate commits. Squash merge collapses them on main, but separate commits on the branch make refactor reviewable and individually revertable.

## Sequence

1. **Verify current tests pass**: run the test suite before touching anything. If tests are already failing, fix them first (separate commit) or flag to the user
2. **Plan structural moves**: identify what's moving where. For renames and file moves, consider blast radius (what references this? what imports change?)
3. **One structural change per commit**: extract a method. Commit. Rename a class. Commit. Move a file. Commit. Each commit should leave tests green
4. **Run tests after each change**: refactoring should never break tests. If a test breaks, your "refactor" changed behavior. Investigate
5. **Update references**: after moves/renames, verify all callers compile. The ecosystem's build catches most; grep for string-based references (config, reflection) the compiler misses

## Checkpoints

- Pre-refactor baseline committed (all tests green)
- Each structural change committed individually with tests green
- Final state committed with full test suite green

## Common pitfalls

- **Mixing structural and behavioral changes**: "while I'm refactoring this class, I'll also add that feature" makes the PR unreviewable and the refactor unrevertable
- **Refactoring without tests**: if code lacks test coverage, add characterization tests first (separate commit, recipe below), then refactor. Otherwise you have no safety net
- **Rewriting instead of refactoring**: a second implementation that replaces the first (rewrite, port, migration) is replace mode, [replace.md](replace.md), not a refactor

## Characterization tests (when the safety net is thin)

A characterization test pins what the code does now, not what it should do. It proves the refactor kept behavior the same; it never proves that behavior correct. Author them through `/testing:write` (when the `testing` plugin is installed); this is the shape it should produce:

1. **Discover the value with a failing assertion.** Feathers' recipe: name the test for the behavior, assert a value you know is wrong, run it, and let the failure report the actual value. Paste that value in. This is the one place an expected value comes from running the code, so mark these tests as pins (in their names or a shared fixture), not as correctness claims
2. **Many outputs or a complex object: use the ecosystem's approval or snapshot tool** instead of hand-pasting each value (for example Verify for .NET, an ApprovalTests port, Jest or Vitest snapshots). Look up the current tool for the stack rather than assuming one. Accepting a received file is a reviewed step, never a blind approve
3. **Scrub volatile values before pinning.** Timestamps, GUIDs, random seeds, ordering and machine paths get a fixed clock, a seed, or the tool's scrubber or property matcher. Never drop the assertion to make it stable
4. **Sabotage check.** Temporarily break the code each pin covers (flip a condition, change a constant), confirm the pin fails, then revert. A pin that stays green under sabotage guards nothing
5. **Commit the pins alone**, before the first structural commit, with the suite green
6. **After the refactor, decide each pin's fate.** A pin that records intended behavior converts into a named behavior test whose expected value has an independent source (`/testing:test-value`). A pin that records incidental output (formatting, ordering nobody relies on) or a bug is deleted, and a pinned bug is reported, never kept as if correct. A pin that later blocks an intended behavior change is updated only after reviewing its diff

- **Pointer**: Feathers' [characterization testing](https://michaelfeathers.silvrback.com/characterization-testing) (the failing-assertion recipe); Seemann's [empirical characterization testing](https://blog.ploeh.dk/2025/11/03/empirical-characterization-testing/) (the sabotage check); review and scrubbing in the tool docs: [Verify scrubbers](https://github.com/VerifyTests/Verify/blob/main/docs/scrubbers.md), [ApprovalTests](https://approvaltests.com/), [Jest snapshot testing](https://jestjs.io/docs/snapshot-testing)
- **As of**: 2026-10-06
- **Recheck trigger**: a tool page above renames its scrubbing or approval mechanism, or `/testing:write` gains its own characterization route (then this section points there instead of carrying the shape)
- **Big-bang refactors**: moving 20 files in one commit. If something breaks, you can't tell which move caused it. Incremental commits are free on feature branches
