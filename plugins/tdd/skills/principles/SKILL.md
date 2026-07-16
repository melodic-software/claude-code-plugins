---
name: principles
description: "Answers test design questions from authoritative TDD sources (Beck, Khorikov), producing WHY reasoning to improve test design decisions. Use when: 'should I mock this', 'four pillars of a good test', 'red green refactor', 'classical vs london school', 'test doubles', 'what makes a good test', 'testing anti-patterns', 'when to mock', 'TDD cycle', 'resistance to refactoring', 'code coverage', 'observable behavior', 'humble object', 'integration test', 'test pyramid', 'output vs state vs communication test' — not for HOW to run tests in your project (use your project's own test tooling and workflow for that)."
argument-hint: "[question or concept]"
user-invocable: true
disable-model-invocation: false
---

# TDD Knowledge Base

Distilled from cover-to-cover reading of source books. Reference files in `reference/` have author-attributed sections with synthesis where authors overlap.

## Routing Table

| Query about... | Load |
|---|---|
| TDD cycle, red-green-refactor, when/why TDD, step size, courage, stress, fear | [methodology-beck.md](reference/methodology-beck.md) |
| What makes a good test, what to test, 3A, Fixture, test naming, parameterized tests | [test-design.md](reference/test-design.md) |
| Mocks, stubs, fakes, mock/stub taxonomy, CQS connection, 5 mocking best practices | [test-doubles.md](reference/test-doubles.md) |
| Refactoring safely, design patterns in TDD, Humble Object, four types of code | [refactoring-under-test.md](reference/refactoring-under-test.md) |
| Four Pillars of a good test, brittle tests, false positives, resistance to refactoring | [four-pillars-khorikov.md](reference/four-pillars-khorikov.md) |
| Code coverage metrics, branch vs statement, goal of unit testing | [code-coverage-khorikov.md](reference/code-coverage-khorikov.md) |
| Classical vs London school, dependency taxonomy, shared/private/out-of-process | [classical-vs-london-khorikov.md](reference/classical-vs-london-khorikov.md) |
| Observable behavior, implementation details, hexagonal architecture, encapsulation | [observable-behavior-khorikov.md](reference/observable-behavior-khorikov.md) |
| Output/state/communication styles, functional architecture, functional core | [testing-styles-khorikov.md](reference/testing-styles-khorikov.md) |
| Four types of code 2x2, Humble Object, CRM refactoring, CanExecute/Execute, domain events, preconditions | [testable-architecture-khorikov.md](reference/testable-architecture-khorikov.md) |
| Integration tests, managed vs unmanaged deps, Test Pyramid, database testing, logging, interfaces, reads vs writes | [integration-testing-khorikov.md](reference/integration-testing-khorikov.md) |
| Anti-patterns: private methods, exposing state, domain knowledge, code pollution, DateTime.Now, time | [anti-patterns-khorikov.md](reference/anti-patterns-khorikov.md) |
| Beck's Money example, Value Object, Expression metaphor, Factory Method | [money-example-beck.md](reference/money-example-beck.md) |
| Beck's xUnit example, bootstrap, Template Method, Composite, Collecting Parameter | [xunit-example-beck.md](reference/xunit-example-beck.md) |

Load the most relevant file first. Load a second only if the first doesn't fully answer.

**Quick decision guide** (no file load needed):

- "Should I write a test for this?" → Yes, unless it's third-party code you trust or trivial code (bottom-left quadrant of the 2x2 matrix: low complexity, few collaborators)
- "Should I mock this?" → Only if it's an unmanaged dependency (message bus, SMTP). Use real instances for managed deps (database)
- "Fake It or Obvious Implementation?" → If confident, Obvious. If surprised by red, back off to Fake It
- "Is this test too big?" → If it needs >3 changes to work, write a smaller Child Test first
- "Test before or after?" → Before. Always. "You won't test after"
- "Output, state, or communication test?" → Output-based first. State-based second. Communication-based only for inter-system with visible side effects
- "Is this code testable?" → Check the 2x2 matrix. High complexity + many collaborators = split it (Humble Object)
- "Should I introduce an interface?" → Only for unmanaged deps you need to mock. Concrete classes for managed deps. Never for in-process deps
- "Should I test this precondition?" → Yes if it has domain significance (e.g., non-negative employees). No if it's purely technical (array length check)
- "Should I test this read operation?" → Higher threshold than writes. Writes corrupt data — always test. Reads: only the most complex/important ones
- "Domain event or direct call?" → Use domain events when the domain model needs to trigger external notifications without depending on out-of-process deps
- "Why is my test brittle?" → It's probably coupled to implementation details. Check: are you asserting on observable behavior or internal structure?

## Sources

- **Beck**: Kent Beck, *Test-Driven Development: By Example* (2003)
- **Khorikov**: Vladimir Khorikov, *Unit Testing: Principles, Practices, and Patterns* (2020)
- **Ousterhout** (secondary, cross-referenced only): John Ousterhout, *A Philosophy of Software Design* — cited in one editorial-synthesis section of [test-doubles.md](reference/test-doubles.md)

## Naming convention

- `{concept}.md` — shared across authors, with attributed sections inside
- `{concept}-{author}.md` — only one author covers it substantively

## Scope boundary

This skill is **knowledge** (WHY behind testing decisions), not **workflow** (HOW to run tests). For running, filtering, or scaffolding tests, use your project's own test tooling, conventions, and workflow skills — this skill informs the design decisions those workflows execute.
