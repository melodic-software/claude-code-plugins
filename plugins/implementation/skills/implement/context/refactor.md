# Refactor Implementation

Refactoring changes structure without changing behavior. Key discipline: **structural commits and behavioral commits are never mixed.**

## The Tidy First Principle

Kent Beck's "Tidy First?" principle: make the change easy, then make the easy change.

- **Tidy (structural)**: rename, extract method/class, move file, reorganize namespace, simplify conditionals
- **Change (behavioral)**: new feature, bug fix, performance improvement

These go in separate commits. Squash merge collapses them on main, but separate commits on the branch make refactor reviewable and individually revertable.

## Sequence

1. **Verify current tests pass**: run the test suite before touching anything. If tests are already failing, fix them first (separate commit) or flag to the user. Then ask of each piece of code you will move: which test fails if it starts returning something else? Where the answer is none, write characterization tests for it first (below). A clean `tsc`, `mypy` or linter run is not an answer: those tools read signatures and never execute the code to see what comes back
2. **Record the UI when the phase has a `**Parity contract:**` line** (when `/testing:check-visual-parity` is among the available skills): run `/testing:check-visual-parity baseline` with the listed screens and states before the first structural edit, then `/testing:check-visual-parity compare` at each green checkpoint of step 6. A failing compare means the refactor changed what users see: stop and investigate it as you would a broken test
3. **Subtract first**: before you plan any move, land a commit that only deletes. Decide what goes by searching, not by feel: run `/code-tidying:audit-dead-code` on the touched paths when it is among the available skills, or grep for each candidate and look for a mention anywhere other than its own definition. In a plugin repository like this one, a search typically turns up a `prerequisites.json` entry for a tool no script runs any more, a wrapper script whose single caller could run the real script itself, and a `case` arm that no caller's input reaches. Delete only what the search shows unused, keep the suite green, and keep that commit free of anything else (characterization pins, if any, land before it)
4. **Plan structural moves**: identify what's moving where. For renames and file moves, consider blast radius (what references this? what imports change?). Next to each move, write what it takes out: a branch, an invalid state the types can no longer hold, or a vague name swapped for one that describes the behavior (step 8). If a move removes none of these and only adds a hop between caller and callee (a new layer, interface or forwarding function), drop it from the plan
5. **One structural change per commit**: extract a method. Commit. Rename a class. Commit. Move a file. Commit. Each commit should leave tests green
6. **Run tests after each change**: refactoring should never break tests. If a test breaks, your "refactor" changed behavior. Investigate. Never edit a test, a recorded baseline or the test harness to turn a run green; if one of them seems mistaken, ask the user before touching it. The one exception is a contract change the approved plan declares: retarget each test written against the old contract to the declared new one, and delete a test whose only subject is internals the change removes. Any other failing test still means behavior changed
7. **Update references**: after moves/renames, verify all callers compile. The ecosystem's build catches most; grep for string-based references (config, reflection) the compiler misses
8. **Name what the reader gains, or revert**: point at one spot where the new code is easier to follow than the old (a branch deleted, one call hop fewer, a name that now says what the code does). With no such spot, revert the reshape and report that it gained nothing

## The old shape (`refactor_compat`)

Before the first structural move, resolve `refactor_compat` per the Resolution section of the [settings page](../../../reference/config.md#resolution), lowest layer first: the default `same-wave`; the user's option, as the SKILL.md Settings table renders it (an unrendered placeholder means unset); and the `refactor_compat` key of the repository's `docs/conventions/implementation.yaml`, read under that page's root rule, which wins when set. A value other than `same-wave` or `deprecate` in either layer is named with its file or option, the key and the value, and that layer is dropped: a valid higher layer still wins, otherwise `same-wave`, never a lower layer's value (ADR 0064 Decision 7). Report one line, for example `refactor_compat: deprecate (docs/conventions/implementation.yaml)`.

Rule: `same-wave` updates all call sites and removes the replaced shape in that same change, unless code outside the repository (a public API, a published package) relies on it; `deprecate` keeps an adapter with a removal condition for every consumer. Every adapter it keeps also carries a time box, a date or release past which it goes even if its removal condition is still unmet, and names the follow-up item that tracks taking it out.

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
