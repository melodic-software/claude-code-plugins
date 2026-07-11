# Organize Tests

Decisions about where tests live, when to create new test projects, how to structure fixtures. Activates when placement or organization decisions are needed.

## Two locations, one rule

**Unit tests co-locate, cross-cutting tests centralize.**

Per-ecosystem naming + locations come from the consuming project's testing conventions (its `CLAUDE.md` / rules / test docs); when undocumented, infer from the project's existing test layout. Placement decisions cite that source rather than inventing new structure.

| Test type | Convention source |
|-----------|-------------------|
| Unit tests | project's unit-test project naming (e.g. `{Project}.Tests` co-located, in .NET) |
| Integration tests (single project) | same convention as unit tests when scoped to one project |
| Integration tests (cross-project) | project's integration-test location (often a central `tests/` root) |
| Architecture tests | project's architecture-test project, when one exists |
| E2E, contract, load, performance | per-repo convention under the integration-test root |

## When to create a new test project

**YES — create a test project when the library has:**

- Business logic, conditional branching, or state management
- Custom implementations of interfaces (not pure delegation)
- Algorithm or transformation logic
- Error handling paths that could fail silently

**NO — skip when the library contains only:**

- Pure contracts (interfaces, attributes, records with no logic)
- Constants (validated by drift guard tests in consumers)
- One-liner delegation methods
- Configuration wiring tested through the repo's E2E orchestrator integration tests

**Transitive coverage is acceptable** when consumer test projects already exercise the contracts.

## Fixture patterns

### Architecture-test project — stays as ONE project per ecosystem

When the project has an architecture-test project, all architecture rules for that ecosystem share one assembly-loading context. Scale via per-app fixtures (one fixture per app, parameterized tests), not separate test projects.

### Collection fixtures — repo-specific shared-state workarounds

Where a process-global singleton, expensive lifecycle, or framework-side limitation forces a specific fixture pattern, the consuming project's testing conventions name the affected projects and the required pattern. Consult them before writing or moving tests under any such project.

## Web SDK child-directory pitfall (.NET-specific)

`Microsoft.NET.Sdk.Web` recursively includes all `.cs` files in subdirectories. **Never** place a test project as a child directory of a Web SDK app. App integration tests go under `integration-test-location` per ecosystem.

## Naming

- Test class: `{ClassUnderTest}Tests`
- Test project: the project's unit-test naming convention (e.g. `{Project}.Tests` for .NET co-located)
- Test file mirrors the structure of the code it tests

## Current state

Track per-repo via the repo's own testing-conventions documentation — architecture test project (if any), integration root, and fixture inventory live there.

## Marketplace plugin skills (invoke only when installed)

- **`dotnet-test:crap-score`** — calculate CRAP (Change Risk Anti-Patterns) scores to prioritize which untested code is riskiest. Combines cyclomatic complexity with coverage data to identify methods where tests would have the highest impact
- **`dotnet-test:test-anti-patterns`** — scan existing test projects for anti-patterns (flakiness indicators, over-mocking, missing assertions, shared static state). Use when assessing test quality during reorganization
