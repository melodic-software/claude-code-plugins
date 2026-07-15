# Feature Implementation

New feature implementation follows a top-down approach: scaffold the structure, fill in implementation, then wire up tests.

## Sequence

1. **Review the plan** — re-read the approved plan. Identify files affected, dependencies, and test strategy
2. **Scaffold first** — create the file/class/interface structure before writing logic. Validates architectural shape before investing in behavior
3. **Inner layers first** — implement Core/Domain types before Application/Infrastructure. Each layer should compile independently as you go
4. **One slice at a time** — for vertical slice features, implement one complete slice (from domain to API endpoint) before starting the next. A working thin slice is more valuable than a half-finished wide one
5. **Test first (TDD by default)** — write the failing test and run it to confirm it fails (red) before writing implementation (Red-Green-Refactor). Invoke `/tdd:principles` via Skill tool (when the `tdd` plugin is installed) for test design guidance: what to test, what to mock, output vs state vs communication, four pillars assessment. For shared libraries, test thoroughly. For app features, test observable behavior not implementation details. Skip test-first only when genuinely impractical (e.g., pure DI wiring or UI rendering with no testable logic behind the seam) — the trigger is *no testable logic*, not the code's layer
6. **Wire up last** — DI registration, middleware configuration, endpoint routing come after feature logic works in isolation

## Checkpoints

Commit after each of these milestones:

- Scaffold committed (interfaces, empty classes, project references)
- First slice working with tests green
- Each subsequent slice working with tests green
- Integration wired up and verified

## Common pitfalls

- **Starting from the outside in** — building the API endpoint before the domain model leads to anemic models shaped by HTTP concerns
- **Implementing everything before testing anything** — large untested batches hide compounding errors
- **Skipping the scaffold commit** — if the scaffold is wrong (wrong project, wrong namespace, wrong layer), you want to revert just the scaffold, not scaffold plus implementation

## Marketplace plugin skills (invoke only when installed)

- **`dotnet-ai:mcp-csharp-create`** — when implementing a new C# MCP server, invoke for scaffolding guidance (project templates, tool/prompt/resource implementation, stdio and HTTP transport configuration)
- **`dotnet-template-engine:template-instantiation`** — when creating a new .NET project, invoke for template selection with CPM adaptation and latest NuGet version resolution
