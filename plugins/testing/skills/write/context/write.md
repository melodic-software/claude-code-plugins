# Write Tests (TDD Mode)

Write tests following the TDD discipline: Red (failing test) -> Green (make it pass) -> Refactor (clean up). Activates when writing new tests for code, whether test-first (TDD) or test-alongside. When uncertain about a testing decision (should I mock this? output or state test? what quadrant is this code in?), load `/tdd:principles` (when the `tdd` plugin is enabled) for authoritative guidance from Beck and Khorikov.

## Vertical slices, not horizontal layers

Write tests and implementation in vertical slices: one test, then the code that passes it, then the next test. Writing every test up front and all the code afterwards is horizontal slicing, which reads Red as "write all the tests" and Green as "write all the code." It yields brittle tests: a test written before any code exists checks the behavior its author *predicted*, not the behavior the code *shows*. Such tests pin the *form* of the code, its data structures and signatures, instead of what a user sees, and they fix the test layout before the implementation is understood. The result: they stay green when behavior breaks and go red when it is correct.

**Correct approach, vertical slices:** a test, its implementation, and again. Each new test builds on what the previous one revealed.

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

- Which parts of the interface does this change add or alter? When the session is interactive and the change is material (a new public surface, a changed contract), confirm with the user; otherwise state the interface you assume and proceed
- Identify opportunities for deep modules: can methods be reduced, params simplified, complexity hidden behind the interface?
- Design interfaces for testability: prefer returning results over producing side effects (testable interfaces return values, making output-based testing possible)
- Proceed once the interface is settled; an autonomous run states its interface assumption in the summary instead of waiting

When invoked from `/implementation:implement` (plan already approved) or as part of a `/testing:write` focused on a single function, skip the Q&A loop: state the interface you assume in one line and proceed.

## Sequence

1. **Tracer bullet first**. Write ONE test confirming ONE thing about the system end-to-end. Proves the path works before investing in edge cases. Use the project's domain glossary (its ubiquitous-language / glossary file when one exists, walking up from the code under test to the nearest one) so the names of tests and interfaces use the domain's own words. Follow any ADRs that govern the code being changed. Then list remaining behavior scenarios:
   - Happy path (basic correct behavior)
   - Edge cases (null, empty, boundary values)
   - Error paths (invalid input, missing dependencies, timeouts)
   - For domain logic: business rules, invariants, state transitions

   You cannot test everything. Focus testing effort on critical paths and complex logic, not every possible edge case.

   When the change has acceptance criteria and a user-visible flow, the tracer bullet is the critical user-flow test, written before the code: see [Outside-in](#outside-in-the-user-flow-test-first).

2. **Choose the test type**. Match the behavior to the right level. Location and framework come from the consuming project's testing conventions (or its existing test projects when undocumented); the role of each row is universal:

   | Behavior | Test type | Location / framework source |
   |----------|-----------|------------------------------|
   | Pure logic, value objects, domain rules | Unit | project's unit-test project convention + framework |
   | HTTP endpoints, middleware, DI wiring | Integration | project's integration-test location + framework |
   | Service orchestration, runtime composition | Integration (orchestrator) | project's orchestrator (Aspire, docker-compose, tilt) + framework |
   | Layer dependencies, naming, conventions | Architecture | project's architecture-test project, when one exists |
   | Critical user journeys end-to-end | E2E | project's browser-automation tooling (see `/testing:run-e2e`) |
   | Parsers, serializers, pure transforms, collections and stateful classes | Property, beside examples | the project's property library; see [property.md](property.md) |
   | Behavior to keep through a replace, migrate or legacy refactor | Characterization, approval or differential (pins) | the project's approval or snapshot tooling; see [characterization.md](characterization.md) |

3. **Write the failing test first** (Red). The test name IS the specification. Use the project's documented naming pattern; when undocumented, mirror the ecosystem's idiom. The forms below are illustrative (.NET/xUnit). Adapt casing/separators to the target ecosystem:
   - Unit: `{Method}_Should{Behavior}_When{Condition}`
   - Integration: `{Subject}_{Behavior}` or `{Subject}_{Behavior}_{Context}`
   - Architecture: `{Subject}_Should{Constraint}`

4. **Make it pass** (Green). Write minimum code. Don't design, don't abstract, don't optimize. Make the test green

5. **Refactor**. Now make it clean. Both test and production code. **Run tests after each refactor step.** All tests must stay green. **Never refactor while RED.** Get to GREEN first, then refactor. Refactoring on a failing test compounds uncertainty. You cannot distinguish refactor breakage from the original failure. Refactor within the slice you just wrote; if the new code reveals a problem in existing code, note it as a follow-up rather than acting on it in this cycle. Refactor candidates beyond duplication extraction:
   - Deepen shallow modules: combine or push complexity behind a simpler interface (Ousterhout: can I reduce methods? simplify params? hide more complexity?)
   - Feature envy (Fowler): logic that sends more messages to another object than its own → Move Method
   - Primitive obsession (Fowler): raw strings/ints representing domain concepts → introduce Value Object
   - Apply SOLID principles where natural. Don't force; let the shape emerge from the tests

6. **Repeat**. Next test scenario from the list

### Per-cycle checklist

After each Red→Green→Refactor cycle, verify:

- [ ] Test describes behavior, not implementation
- [ ] Test uses public interface only
- [ ] Test would survive internal refactor
- [ ] One logical assertion per test: one behavioral concept, not one `Assert` statement
- [ ] Every expected value names its independent source, per `testing:test-value`; a round trip or identity check (`decode(encode(x))` equals `x`) passes when both directions share a mistake, so pair it with a known encoded fixture
- [ ] Existing coverage does not already catch this regression. Each contract has one primary test at its strongest boundary; another layer needs a risk of its own, such as a transport failure the primary test cannot reach. Extend a table-driven case before adding a near-duplicate
- [ ] A bug fix adds one regression test at the boundary that owns the bug, not one per layer the bug crosses
- [ ] The test needs no export, flag or injection hook that no production caller uses; if it does, test through the real boundary instead
- [ ] Code is minimal for this test
- [ ] No speculative features added

## Four Pillars Assessment (Khorikov)

Every test should score well on all four:

- **Protection against regressions**. Does this test catch real bugs? Tests that only verify trivial behavior (getters, constructors) score low
- **Resistance to refactoring**. Will this test break when implementation changes but behavior stays the same? Test behavior (observable output), not implementation (internal steps)
- **Fast feedback**. Does this test run quickly? Slow tests get skipped. As a rough bar, a unit test well under 100ms and an integration test under 5s; that bar is this repository's own heuristic, not a sourced standard (Khorikov's pillar sets no number)
- **Maintainability**. Is this test easy to understand and change? No test should be harder to read than the code it tests

## Determinism controls

A test that passes or fails by chance teaches the agent running it to retry instead of fix. Build these in when the test is written, not after it flakes:

- **Clock**: inject the clock (a parameter, an interface, the framework's time provider) or use the test framework's fake clock. Code under test never reads wall time directly
- **Randomness**: seed the random generator per test and print the seed in the failure output, so a failure replays with the same seed
- **Network**: blocked by default in unit tests; an integration test opts in to the hosts it needs. External services are faked from a recorded or documented response, not a guessed one
- **No sleep**: wait on a condition with a timeout, or advance the fake clock. A fixed sleep is slow when it is long enough and flaky when it is not
- **Order independence**: each test builds its own state and leaves nothing another test reads. Run the suite in shuffled order (with a printed seed) to prove it
- **Parallel safety**: unique temp directories, ports, database names and file paths per test; no shared mutable singletons

Runner-level switches exist for several of these (a fake clock in Playwright, seeded shuffling and per-test reseeding in pytest-randomly and `go test -shuffle`, socket blocking in pytest-socket). Read the current options at the source: [Playwright clock](https://playwright.dev/docs/clock), [pytest-randomly](https://github.com/pytest-dev/pytest-randomly), [pytest-socket](https://github.com/miketheman/pytest-socket). As of 2026-10-06. Recheck trigger: a tool renames or drops the switch. Whether to fake a dependency at all follows `/tdd:principles` (when the `tdd` plugin is enabled).

## Outside-in: the user-flow test first

When the change has acceptance criteria and a user-visible flow (a page, an API call, a CLI command):

1. **Write the critical user-flow test before the code**, from the acceptance criteria: the steps a user takes and the outcome the criteria state. It fails (Red). One test per critical journey, not one per criterion
2. **Keep it as the oracle for the whole task.** Run it after each slice; the task is not done until it passes. Never change its expectation to match what the code does. If the criteria turn out wrong, change them with the user first, then the test
3. **Work inside it** with unit and integration tests in vertical slices, as above. The pyramid below still decides how many of each

Name the costs. E2E tests are slower and flakier, and a failure does not say which component broke (poor fault isolation): the standard criticism, made in Wacker's 2015 Google Testing Blog post. Offset them: keep the flow count small, retain a trace on failure, and use the failure evidence `/testing:run-e2e` captures (failing step, expected against actual, trace, console and network errors) so the failure report becomes the next prompt. Fault isolation comes from the unit tests inside.

Basis: LLM-written test oracles were measured to assert what the code does rather than what it should do (three papers, measured on LLM test generators over benchmark repositories; the transfer to an interactive agent is inferred). A test written from acceptance criteria before the code exists cannot copy the code's behavior. Recorded in the agent-self-check research slice, 2026-10-06, prompted by Addy Osmani's 2026-10-05 post (<https://x.com/addyosmani/status/2106995301802541481>). Recheck trigger: a measurement on interactive coding agents that contradicts it. For acceptance tests written by a separate agent, see [blind-author.md](blind-author.md).

## Verify through the interface, not around it

A managed database (one only your application touches) is real: reading the row back after the act step is legitimate state verification, as long as the test asserts the fields rather than that a row exists. What couples a test to the implementation is reading internal tables the public contract never exposes when a public read path exists. `testing:test-value` §3 owns the rule. Illustrative: .NET/xUnit; the principle is ecosystem-agnostic:

```csharp
// GOOD: state verification of a managed database, asserting the fields
[Fact]
public async Task CreateUser_StoresTheUser()
{
    var user = await _sut.CreateUser(new("Alice"));
    var row = await _db.QuerySingleAsync<UserRow>("SELECT * FROM Users WHERE Id = @Id", new { user.Id });
    Assert.Equal("Alice", row.Name);
}

// BAD: reads an internal index table the contract never exposes, while SearchUsers is the public read path
[Fact]
public async Task CreateUser_IndexesTheName()
{
    await _sut.CreateUser(new("Alice"));
    var key = await _db.ExecuteScalarAsync<string>("SELECT NormalizedName FROM UserSearchIndex");
    Assert.Equal("ALICE", key);
}
```

When no public read path exists and the stored state is not the contract, reaching around the interface is a design signal: the interface is missing an observable output.

## Test Pyramid vs Testing Trophy

- **Backend (domain + application layers)**. Follow the test pyramid (Fowler): many unit tests, moderate integration, few E2E. Domain logic is well-suited to isolated unit testing
- **Frontend / API boundary (endpoints, middleware, UI)**. Lean toward the testing trophy (Dodds): weight integration tests more heavily. "Write tests. Not too many. Mostly integration." Component interactions at the boundary are where bugs actually hide
- **Architecture rules**. Always run the architecture-rules test suite when the project has one. Cheap, fast, and it catches structural drift before it compounds

## When NOT to write tests

No tests needed for:

- Pure contracts (interfaces, attributes, records with no logic)
- Constants (validated by drift guard tests in consumers)
- One-liner delegation methods
- Configuration wiring tested end-to-end through the repo's E2E orchestrator

The list above is about code that needs no test. A second, different question is whether a test
worth having is worth *this* test, and the answer is sometimes no even for code that does need
covering. **Prefer no new test to a bad one** when the only
available test would need broad harness setup, brittle mocks, slow end-to-end infrastructure,
production-only state, a reproduction nobody can state precisely, or large unrelated fixture churn.
A test that mostly exercises its own mocks, encodes today's implementation, or would be deleted the
moment it has proved its point costs more to maintain than the confidence it buys.

Declining is not skipping. Say which of those made the test impractical, then name the closest
executable check you used instead: a targeted script, a reproduction command, a snapshot
comparison, a log assertion, a focused integration check. A decline with a named substitute is a
decision; a decline with silence is a gap nobody can see.

## Commit discipline

- **Failing test committed** (optional but valuable). Proves the bug/requirement exists in git history
- **Fix + green test committed together**. The fix and its proof are atomic
- **Commit before refactoring**. Separate structural from behavioral commits
