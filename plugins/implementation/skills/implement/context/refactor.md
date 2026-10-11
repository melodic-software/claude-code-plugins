# Refactor Implementation

Refactoring changes structure without changing behavior. Key discipline: **structural commits and behavioral commits are never mixed.**

## The Tidy First Principle

Kent Beck's "Tidy First?" principle: make the change easy, then make the easy change.

- **Tidy (structural)**: rename, extract method/class, move file, reorganize namespace, simplify conditionals
- **Change (behavioral)**: new feature, bug fix, performance improvement

These go in separate commits. Squash merge collapses them on main, but separate commits on the branch make refactor reviewable and individually revertable.

## Sequence

1. **Verify current tests pass**: run the test suite before touching anything. If tests are already failing, fix them first (separate commit) or flag to the user. A passing typecheck or lint is not a pin: it shows the signatures still fit, not that each call still returns what it did, so code no test exercises gets characterization tests first (below)
2. **Record the UI when the phase has a `**Parity contract:**` line** (when `/testing:check-visual-parity` is among the available skills): run `/testing:check-visual-parity baseline` with the listed screens and states before the first structural edit, then `/testing:check-visual-parity compare` at each green checkpoint of step 6. A failing compare means the refactor changed what users see: stop and investigate it as you would a broken test
3. **Subtract first**: before planning any move, list what the touched area can lose: imports and config keys that point at things already gone, wrappers whose single caller could call the target directly, and branches no input reaches any more. Run `/code-tidying:audit-dead-code` on the touched paths when it is among the available skills; otherwise grep each candidate for a reference outside its own definition. Delete what the evidence shows unused and commit those deletions alone, with the suite green, as the first refactor commit (after any characterization pins)
4. **Plan structural moves**: identify what's moving where. For renames and file moves, consider blast radius (what references this? what imports change?). Keep a move only when it removes a branch, makes an invalid state impossible to represent, or gives the code a name that says what it does (step 8); a move that only adds indirection (a new layer, interface or pass-through between caller and callee) is dropped
5. **One structural change per commit**: extract a method. Commit. Rename a class. Commit. Move a file. Commit. Each commit should leave tests green
6. **Run tests after each change**: refactoring should never break tests. If a test breaks, your "refactor" changed behavior. Investigate. Never edit a test, a recorded baseline or the test harness to turn a run green; if one of them seems mistaken, ask the user before touching it. The one exception is a contract change the approved plan declares: retarget each test written against the old contract to the declared new one, and delete a test whose only subject is internals the change removes. Any other failing test still means behavior changed
7. **Update references**: after moves/renames, verify all callers compile. The ecosystem's build catches most; grep for string-based references (config, reflection) the compiler misses
8. **Keep it only if reading got easier**: name the place a reader now has less to hold, such as a branch gone, a hop removed or a name that now says what the code does. If you cannot name one, revert the reshape and report that it did not pay off

## The old shape (`refactor_compat`)

Before the first structural move, resolve `refactor_compat` per the Resolution section of the [settings page](../../../reference/config.md#resolution), lowest layer first: the default `same-wave`; the user's option, as SKILL.md Step 0 renders it (an unrendered placeholder means unset); and the `refactor_compat` key of the repository's `docs/conventions/implementation.yaml`, read under that page's root rule, which wins when set. A value other than `same-wave` or `deprecate` in either layer is named with its file or option, the key and the value, and that layer is dropped: a valid higher layer still wins, otherwise `same-wave`, never a lower layer's value (ADR 0060 Decision 7). Report one line, for example `refactor_compat: deprecate (docs/conventions/implementation.yaml)`.

Rule: `same-wave` updates all call sites and removes the replaced shape in that same change, unless code outside the repository (a public API, a published package) relies on it; `deprecate` keeps an adapter with a removal condition for every consumer, and each kept adapter also names a time box (the date or release after which it is removed even if the condition has not been met) and the follow-up item that tracks its removal.

## Checkpoints

- Pre-refactor baseline committed (all tests green)
- Each structural change committed individually with tests green
- Final state committed with full test suite green

## Common pitfalls

- **Mixing structural and behavioral changes**: "while I'm refactoring this class, I'll also add that feature" makes the PR unreviewable and the refactor unrevertable
- **Refactoring without tests**: if code lacks test coverage, add characterization tests first (separate commit, recipe below), then refactor. Otherwise you have no safety net
- **Rewriting instead of refactoring**: a second implementation that replaces the first (rewrite, port, migration) is replace mode, [replace.md](replace.md), not a refactor

## Characterization tests (when the safety net is thin)

A characterization test pins what the code does now, not what it should do. It proves the refactor kept behavior the same; it never proves that behavior correct. Author them through `/testing:write`, whose characterization route owns the recipe, the sabotage check, scrubbing and each pin's fate after the change (when the `testing` plugin is installed). The refactor-specific part is the order: **commit the pins alone, before the first structural commit, with the suite green**, so the history shows the baseline the refactor kept.

- **Big-bang refactors**: moving 20 files in one commit. If something breaks, you can't tell which move caused it. Incremental commits are free on feature branches
