# Unit Testing Anti-Patterns (Khorikov)

Six anti-patterns analyzed through the Four Pillars framework: testing private methods, exposing private state, leaking domain knowledge, code pollution, mocking concrete classes, and time as ambient context (Ch 11). Each anti-pattern looks reasonable on the surface but leads to problems, primarily by coupling tests to implementation details and damaging resistance to refactoring.

## 1. Unit Testing Private Methods

### The Rule: Don't Test Private Methods Directly

> "Exposing methods that you would otherwise keep private just to enable unit testing violates one of the foundational principles: testing observable behavior only."

Testing private methods couples tests to implementation details, damaging resistance to refactoring, the most important of the Four Pillars. Instead, test private methods indirectly through the public API.

### When a Private Method Seems Too Complex to Cover Indirectly

If the observable behavior doesn't provide sufficient coverage for a complex private method, two issues may be at play:

1. **Dead code**: the private method contains unused logic left after a refactoring. Delete it
2. **Missing abstraction**: the private method contains important logic that deserves its own class

Extract that logic into its own class (for example, price calculation pulled out of an order, taking the customer and products as explicit inputs). It is then reachable through a public method, testable with output-based testing. No hidden inputs or outputs.

### The Rare Exception: Private Methods That Are Observable Behavior

In rare cases, a private method is both private AND part of observable behavior. Example: a class with a private constructor used by an ORM to restore objects from the database.

The private constructor fulfills the ORM contract. It's observable behavior from the ORM's perspective. Making it public (with proper preconditions) won't lead to test brittleness and arguably improves the API design. Alternative: use reflection to instantiate in tests (mirrors what the ORM does).

## 2. Exposing Private State for Testing

> **"Your tests should interact with the system under test exactly the same way as the production code and shouldn't have any special privileges."**

Don't expose private fields/properties just to assert on them. Instead, test through what the production code actually observes.

Example: a customer whose private status field decides its discount. Don't make the status field public for testing. The production code reads the discount, so test through that:

- A newly created customer has no discount (0%)
- Once promoted, the discount becomes 5%

If the production code later starts using the status directly, it would naturally become part of the observable behavior and should then be public.

> "Widening the public API surface for the sake of testability is a bad practice."

## 3. Leaking Domain Knowledge to Tests

Tests that reproduce the production algorithm in the arrange section are **tautology tests**. They couple to implementation details and have near-zero resistance to refactoring.

> **"Don't imply any specific implementation when writing tests."** Hardcode expected results. For complex algorithms, precalculate expected values with the help of a domain expert or (for legacy refactoring) use the old system's output as the expected baseline.

This may seem counterintuitive, but hardcoded values provide an independent checkpoint. Tests that duplicate the algorithm become a mirror. If the algorithm changes, developers copy-paste the new version into the test without investigating whether the change is correct.

## 4. Code Pollution

> **Code pollution** is adding production code that's only needed for testing.

The classic form is a Boolean switch: a flag that makes production code skip its work under test.

Code pollution mixes test and production concerns, increasing maintenance costs. The test-only code path can be accidentally invoked in production.

**Fix**: introduce an interface with separate implementations, a real one for production and a fake one in test code only.

The interface is technically a mild form of code pollution (it exists partly for testing), but it's far less damaging. Interfaces have no code, can't harbor bugs, and can't accidentally trigger production behavior.

## 5. Mocking Concrete Classes

When a class combines domain logic with out-of-process communication, mocking it partially (overriding only the communication method while keeping the real domain logic) is tempting but is an anti-pattern.

> "The necessity to mock a concrete class in order to preserve part of its functionality is a result of violating the Single Responsibility principle."

**Fix**: split into two classes using the Humble Object pattern: an interface-backed gateway for the communication and a pure calculator, with no out-of-process dependencies, for the domain logic.

The controller orchestrates: calls the gateway, passes results to the calculator. The gateway gets mocked (unmanaged dependency); the calculator is tested directly (domain logic). No need to mock concrete classes.

## 6. Working with Time

Three approaches to stabilizing time in tests:

### Anti-Pattern: Time as Ambient Context

A static, mutable time provider that production initializes with the system clock and tests initialize with a fixed date **pollutes** production code with test infrastructure, makes the dependency hidden, and introduces a shared static field that prevents test parallelization.

### Good: Time as an Explicit Dependency

Two sub-options:

- **As a service**: the controller receives a time provider and passes its current value to the domain method.
- **As a plain value**: the caller passes the current time directly to the domain method.

> "Prefer injecting the time as a value rather than as a service. It's easier to work with plain values in production code, and it's also easier to stub those values in tests."

**Khorikov's recommended compromise**: inject time as a service at the controller level (DI-friendly), then pass it as a plain value to domain classes.

## Quick Reference

| Anti-Pattern | Core Problem | Fix |
|---|---|---|
| Testing private methods | Couples to implementation details | Test through public API; extract missing abstractions |
| Exposing private state | Tests get special privileges production code doesn't have | Assert through observable behavior (what production code sees) |
| Leaking domain knowledge | Test duplicates the algorithm (tautology test) | Hardcode expected values; precalculate with domain expert |
| Code pollution | Production code contains test-only paths | Interface + separate implementations (real + fake) |
| Mocking concrete classes | SRP violation forces partial mocking | Split into gateway (mockable) + calculator (testable directly) |
| Time as ambient context | Hidden dependency, shared state, pollution | Inject time as service at controller; pass as value to domain |
