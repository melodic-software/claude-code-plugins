# Write Tests (TDD Mode)

Write tests following the TDD discipline: Red (failing test) -> Green (make it pass) -> Refactor (clean up). Activates when writing new tests for code — whether test-first (TDD) or test-alongside. When uncertain about a testing decision (should I mock this? output or state test? what quadrant is this code in?), load `/tdd:principles` (when the `tdd` plugin is installed) for authoritative guidance from Beck and Khorikov.

## Vertical slices, not horizontal layers

**DO NOT write all tests first, then all implementation.** That is horizontal slicing — treating Red as "write all tests" and Green as "write all code." Horizontal slicing produces brittle tests: tests written in bulk test *imagined* behavior, not *actual* behavior. You end up testing the *shape* of things — data structures, function signatures — rather than user-facing behavior. You commit to test structure before understanding implementation, then tests become insensitive to real changes — they pass when behavior breaks, fail when behavior is fine.

**Correct approach — vertical slices:** one test → one implementation → repeat. Each test responds to what you learned from the previous cycle.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
```

This is the test-level instance of the same vertical-not-horizontal discipline `/implementation:implement` applies to plan phases and execution.

## Pre-coding interface check

Before writing the first test, confirm the public interface design:

- What interface changes are needed? Confirm with the user
- Identify opportunities for deep modules — can methods be reduced, params simplified, complexity hidden behind the interface?
- Design interfaces for testability — prefer returning results over producing side effects (testable interfaces return values, making output-based testing possible)
- Get user approval on the plan before writing test code

When invoked from `/implementation:implement` (plan already approved) or as part of a `/testing:write` focused on a single function, scale this step to a quick self-check rather than a full Q&A loop.

## Sequence

1. **Tracer bullet first** — write ONE test confirming ONE thing about the system end-to-end. Proves the path works before investing in edge cases. Use the project's domain glossary (its ubiquitous-language / glossary file when one exists — walk up from the code under test to the nearest one) so test names and interface vocabulary match the domain language. Respect ADRs in the area you're touching. Then list remaining behavior scenarios:
   - Happy path (basic correct behavior)
   - Edge cases (null, empty, boundary values)
   - Error paths (invalid input, missing dependencies, timeouts)
   - For domain logic: business rules, invariants, state transitions

   You cannot test everything. Focus testing effort on critical paths and complex logic, not every possible edge case.

2. **Choose the test type** — match the behavior to the right level. Location and framework come from the consuming project's testing conventions (or its existing test projects when undocumented); the role of each row is universal:

   | Behavior | Test type | Location / framework source |
   |----------|-----------|------------------------------|
   | Pure logic, value objects, domain rules | Unit | project's unit-test project convention + framework |
   | HTTP endpoints, middleware, DI wiring | Integration | project's integration-test location + framework |
   | Service orchestration, runtime composition | Integration (orchestrator) | project's orchestrator (Aspire, docker-compose, tilt) + framework |
   | Layer dependencies, naming, conventions | Architecture | project's architecture-test project, when one exists |
   | Critical user journeys end-to-end | E2E | project's browser-automation tooling (see `/testing:run-e2e`) |

3. **Write the failing test first** (Red) — the test name IS the specification:
   - Unit: `{Method}_Should{Behavior}_When{Condition}`
   - Integration: `{Subject}_{Behavior}` or `{Subject}_{Behavior}_{Context}`
   - Architecture: `{Subject}_Should{Constraint}`

4. **Make it pass** (Green) — write minimum code. Don't design, don't abstract, don't optimize. Make the test green

5. **Refactor** — now make it clean. Both test and production code. **Run tests after each refactor step** — all tests must stay green. **Never refactor while RED.** Get to GREEN first, then refactor. Refactoring on a failing test compounds uncertainty — you cannot distinguish refactor breakage from the original failure. Consider what new code reveals about existing code — new code is a lens on old code; refactoring is the time to act on what you see. Refactor candidates beyond duplication extraction:
   - Deepen shallow modules — combine or push complexity behind a simpler interface (Ousterhout: can I reduce methods? simplify params? hide more complexity?)
   - Feature envy (Fowler) — logic that sends more messages to another object than its own → Move Method
   - Primitive obsession (Fowler) — raw strings/ints representing domain concepts → introduce Value Object
   - Apply SOLID principles where natural — don't force; let the shape emerge from the tests

6. **Repeat** — next test scenario from the list

### Per-cycle checklist

After each Red→Green→Refactor cycle, verify:

- [ ] Test describes behavior, not implementation
- [ ] Test uses public interface only
- [ ] Test would survive internal refactor
- [ ] One logical assertion per test — one behavioral concept, not one `Assert` statement
- [ ] No tautological assertions — expected values are independently sourced (literal, hand-computed, known fixture), never recomputed the same way the code under test computes them; a round-trip/identity check of output against input proves nothing (detection layer: `dotnet-test:test-anti-patterns` + `dotnet-test:assertion-quality` plugins)
- [ ] Code is minimal for this test
- [ ] No speculative features added

## Four Pillars Assessment (Khorikov)

Every test should score well on all four:

- **Protection against regressions** — does this test catch real bugs? Tests that only verify trivial behavior (getters, constructors) score low
- **Resistance to refactoring** — will this test break when implementation changes but behavior stays the same? Test behavior (observable output), not implementation (internal steps)
- **Fast feedback** — does this test run quickly? Unit tests: <100ms. Integration: <5s. Slow tests get skipped
- **Maintainability** — is this test easy to understand and change? No test should be harder to read than the code it tests

## Verify through the interface, not around it

Tests that bypass the public interface to verify side effects are coupled to implementation. Verify through the same interface callers use:

```csharp
// BAD: Bypasses interface — coupled to storage implementation
[Fact]
public async Task CreateUser_SavesUserToDatabase()
{
    await _sut.CreateUser(new("Alice"));
    var row = await _db.QuerySingleAsync("SELECT * FROM Users WHERE Name = @Name", new { Name = "Alice" });
    Assert.NotNull(row);
}

// GOOD: Verifies through public interface — survives storage refactor
[Fact]
public async Task CreateUser_MakesUserRetrievable()
{
    var user = await _sut.CreateUser(new("Alice"));
    var retrieved = await _sut.GetUser(user.Id);
    Assert.Equal("Alice", retrieved.Name);
}
```

If the only way to verify is by reaching around the interface (querying DB directly, inspecting file system, checking internal state), that is a design signal — the interface is missing an observable output.

## Test Pyramid vs Testing Trophy

- **Backend (domain + application layers)** — follow the test pyramid (Fowler): many unit tests, moderate integration, few E2E. Domain logic is well-suited to isolated unit testing
- **Frontend / API boundary (endpoints, middleware, UI)** — lean toward the testing trophy (Dodds): weight integration tests more heavily. "Write tests. Not too many. Mostly integration." Component interactions at the boundary are where bugs actually hide
- **Architecture rules** — always run an architecture-rules test suite when the ecosystem has one configured (`architecture-test-project` per ecosystem). Cheap, fast, catches structural drift before it compounds

## When NOT to write tests

No tests needed for:

- Pure contracts (interfaces, attributes, records with no logic)
- Constants (validated by drift guard tests in consumers)
- One-liner delegation methods
- Configuration wiring tested end-to-end through the repo's E2E orchestrator

## Commit discipline

- **Failing test committed** (optional but valuable) — proves the bug/requirement exists in git history
- **Fix + green test committed together** — the fix and its proof are atomic
- **Commit before refactoring** — separate structural from behavioral commits

## Marketplace plugin skills

When writing tests, consider loading these marketplace plugin skills for guidance:

- **`dotnet-test:code-testing-agent`** — multi-agent pipeline for comprehensive test generation (researcher → planner → implementer → builder → tester → fixer → linter). Invoke for complex test scenarios requiring gap analysis and structured implementation
