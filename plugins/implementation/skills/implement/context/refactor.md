# Refactor Implementation

Refactoring changes structure without changing behavior. Key discipline: **structural commits and behavioral commits are never mixed.**

## The Tidy First Principle

Kent Beck's "Tidy First?" principle: make the change easy, then make the easy change.

- **Tidy (structural)**: rename, extract method/class, move file, reorganize namespace, simplify conditionals
- **Change (behavioral)**: new feature, bug fix, performance improvement

These go in separate commits. Squash merge collapses them on main, but separate commits on the branch make refactor reviewable and individually revertable.

## Sequence

1. **Verify current tests pass** — run the test suite before touching anything. If tests are already failing, fix them first (separate commit) or flag to the user
2. **Plan structural moves** — identify what's moving where. For renames and file moves, consider blast radius (what references this? what imports change?)
3. **One structural change per commit** — extract a method. Commit. Rename a class. Commit. Move a file. Commit. Each commit should leave tests green
4. **Run tests after each change** — refactoring should never break tests. If a test breaks, your "refactor" changed behavior — investigate
5. **Update references** — after moves/renames, verify all callers compile. The ecosystem's build catches most; grep for string-based references (config, reflection) the compiler misses

## Checkpoints

- Pre-refactor baseline committed (all tests green)
- Each structural change committed individually with tests green
- Final state committed with full test suite green

## Common pitfalls

- **Mixing structural and behavioral changes** — "while I'm refactoring this class, I'll also add that feature" makes the PR unreviewable and the refactor unrevertable
- **Refactoring without tests** — if code lacks test coverage, add characterization tests first (separate commit), then refactor. Otherwise you have no safety net
- **Big-bang refactors** — moving 20 files in one commit. If something breaks, you can't tell which move caused it. Incremental commits are free on feature branches

## Marketplace plugin skills (invoke only when installed)

- **`dotnet-msbuild:msbuild-antipatterns`** — after moving types across projects, invoke to scan changed .csproj/.props/.targets for anti-patterns introduced by the restructuring (missing PrivateAssets, stale references, unconditional overrides)
- **`dotnet-msbuild:resolve-project-references`** — when renaming or moving projects, invoke to detect broken or circular references in the MSBuild dependency graph before committing
