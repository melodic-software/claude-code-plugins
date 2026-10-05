# Feature Implementation

New feature implementation follows a top-down approach: scaffold the structure, fill in implementation, then wire up tests.

**Posture.** With an approved plan, its work items set how far the feature reshapes existing code. With none, apply the `integration_posture` that Step 0 resolved: `by-kind` or `day-one` redesigns the code the feature lands in, `minimal` adds the feature with the smallest change.

## Sequence

1. **Review the plan**: re-read the approved plan. Identify files affected, dependencies, and test strategy
2. **Scaffold first**: create the file/class/interface structure before writing logic. Validates architectural shape before investing in behavior
3. **Depended-upon parts first**: implement the components others depend on before their dependents, following the project's own dependency direction, so each compiles against something that already exists. In a layered .NET/Clean-Architecture app, for example, that means Core/Domain types before Application/Infrastructure
4. **One slice at a time**: for vertical slice features, implement one complete slice (from domain to API endpoint) before starting the next. A working thin slice is more valuable than a half-finished wide one
5. **Test first (TDD by default when project policy is silent)**: first honor the consuming project's testing cadence from its `CLAUDE.md` / rules; that project policy overrides the test-first instructions in this step. When the project declares no cadence, write the failing test and run it to confirm it fails (red) before writing implementation (Red-Green-Refactor). Invoke `/tdd:principles` via Skill tool (when the `tdd` plugin is installed) for test design guidance: what to test, what to mock, output vs state vs communication, four pillars assessment. For shared libraries, test thoroughly. For app features, test observable behavior not implementation details. Under the fallback cadence, skip test-first only when genuinely impractical (e.g., pure DI wiring or UI rendering with no testable logic behind the seam). The trigger is *no testable logic*, not the code's layer
6. **Wire up last**: DI registration, middleware configuration, endpoint routing come after feature logic works in isolation

## Checkpoints

Commit after each of these milestones:

- Scaffold committed (interfaces, empty classes, project references)
- First slice working with tests green
- Each subsequent slice working with tests green
- Integration wired up and verified

## Common pitfalls

- **Starting from the outside in**: building the API endpoint before the domain model leads to anemic models shaped by HTTP concerns
- **Implementing everything before testing anything**: large untested batches hide compounding errors
- **Skipping the scaffold commit**: if the scaffold is wrong (wrong project, wrong namespace, wrong layer), you want to revert just the scaffold, not scaffold plus implementation
- **Building beyond the slice**: implementing options, hooks, or abstractions the plan did not ask for; add them when a second caller exists, not in anticipation of one

## Ecosystem scaffolding skills (invoke only when installed)

When the session's skill listing carries a scaffolding skill for the artifact being created (a C# MCP-server scaffold with transport configuration, a .NET project-template instantiation skill with package-version resolution), invoke it for scaffolding guidance; otherwise fall back to the project's own scaffolding tooling. Resolve the skill from what is actually installed; never invent a skill name.
