# Observable Behavior, Mocks, and Test Fragility (Khorikov)

Observable behavior vs implementation details, the mock/stub taxonomy, hexagonal architecture, intra vs inter-system communications, and when mocking is legitimate (Ch 5). This chapter connects the Four Pillars to concrete mocking guidance.

## The Mock/Stub Taxonomy

All five test double types (dummy, stub, spy, mock, fake) collapse into two categories:

```
Test double
├── Mock (mock, spy)     → emulate and examine OUTGOING interactions
└── Stub (stub, dummy, fake) → emulate INCOMING interactions
```

- **Mocks** help emulate and examine *outgoing* interactions: calls the SUT makes to its dependencies to **change their state** (side effects)
- **Stubs** help emulate *incoming* interactions: calls the SUT makes to its dependencies to **get input data**

**Spies** are handwritten mocks (same role, manually coded instead of using a framework). **Dummies** are simple hardcoded values (null, a made-up string). **Fakes** are fully fledged replacement dependencies, usually for something that doesn't exist yet.

### Don't Assert Interactions with Stubs

> "Asserting interactions with stubs is a common anti-pattern that leads to fragile tests."

A call from the SUT to a stub is not part of the end result. It's a means to produce the end result. Verifying it is **overspecification**.

### When a Double Is Both Mock and Stub

A single test double can serve both roles. The store double from Chapter 2's London-style test provides canned answers (stub role) and verifies calls (mock role). When a double serves both, it's still called a mock. Being a mock is the more important fact.

### CQS Connection

The mock/stub distinction maps directly to Command Query Separation:

| CQS | Side effects? | Returns? | Test double |
|-----|--------------|----------|-------------|
| **Command** | Yes | void | Mock |
| **Query** | No | Value | Stub |

> "Test doubles that substitute commands become mocks. Similarly, test doubles that substitute queries are stubs."

## Observable Behavior vs Implementation Details

### Two Independent Dimensions

All production code can be categorized along two dimensions:

1. **Public API** vs **Private API**: visibility to clients
2. **Observable behavior** vs **Implementation detail**: purpose

These don't automatically align. A method can be public yet be an implementation detail (leaking API).

### What Makes Code Observable Behavior

For code to be part of observable behavior, it must do one of:

- **Expose an operation** that helps the client achieve one of its goals
- **Expose a state** that helps the client achieve one of its goals

Anything else is an implementation detail, regardless of whether it's public or private.

### Well-Designed API = Public API Coincides with Observable Behavior

| | Observable behavior | Implementation detail |
|---|---|---|
| **Public** | Good | Bad (leaking) |
| **Private** | N/A | Good |

> "Making the API well-designed automatically improves unit tests."

When all implementation details are private, tests have no choice but to verify observable behavior, which automatically improves resistance to refactoring.

### The Leaking API Problem

A `User` class that exposes a public `NormalizeName` operation beside its `Name` makes the client normalize a new name and then assign it: two operations for one goal. `NormalizeName` is an implementation detail. The client's goal is to change the name, not to normalize it. Fix: make it private and apply it whenever the name is assigned, so the client changes the name in one operation.

**Rule of thumb:** *"Ideally, any individual goal should be achieved with a single operation."* If the client must invoke multiple operations to achieve one goal, the class is leaking implementation details.

### Encapsulation Connection

Exposing implementation details goes hand-in-hand with invariant violations. The original `User` let clients bypass normalization. A well-designed API eliminates the *possibility* of doing the wrong thing.

<!-- ai-slop-ignore-start: verbatim Khorikov quotation, dash is inside the quoted sentence -->
> "You cannot trust yourself to do the right thing all the time — so, eliminate the very possibility of doing the wrong thing."
<!-- ai-slop-ignore-end -->

## Hexagonal Architecture

A typical application has two layers:

- **Domain layer** (center): business logic, the *how-to's*
- **Application services layer** (outer): orchestrates domain classes with out-of-process dependencies, the *what-to's*

Three guidelines (Alistair Cockburn):

1. **Separation of concerns**: domain handles business logic only; app services handle external communication
2. **One-way dependency flow**: app services → domain (never reverse). Domain must be fully isolated from the external world
3. **Inter-application communication** through the app services layer, with no direct access to the domain from outside

### Fractal Nature

Each layer exhibits its own observable behavior relative to its client. Domain class behavior helps the app service achieve its goals. App service behavior helps the external client achieve its goals. Tests at each level verify behavior at that level.

## Intra-System vs Inter-System Communications

This is the central insight of the chapter:

> "Intra-system communications are implementation details; inter-system communications are not."

- **Intra-system** = between classes inside the application. The collaborations domain classes go through to perform an operation are not part of observable behavior. They don't have an immediate connection to the client's goal
- **Inter-system** = between the application and external systems. The way your system talks to the external world forms the observable behavior (contract) of that system as a whole. Must be maintained for backward compatibility

### When Mocking Is Legitimate

**Mock inter-system communications (observable behavior).** When a purchase sends a receipt through the SMTP service, that call crosses the application boundary and is visible externally, so a test may verify it with a mock.

**Don't mock intra-system communications (implementation details).** The `RemoveInventory()` call from `Customer` to `Store` doesn't cross the application boundary. It's an intermediate step, an implementation detail. Mocking it couples the test to *how* the purchase happens, not *what* happens.

## Not All Out-of-Process Dependencies Should Be Mocked

> "If an out-of-process dependency is only accessible through your application, then communications with such a dependency are not part of your system's observable behavior."

**Application database** (only your app accesses it) → implementation detail → don't mock. You can split tables, change stored procedures, even replace the storage engine, and clients won't notice. The database and your application must be treated as one system.

**SMTP service, message bus, third-party APIs** (visible to external clients) → observable behavior → mock.

## The "Mocks Verify Behavior" Misconception

> "Mocks are often said to verify behavior. In the vast majority of cases, they don't."

Class-to-class interactions are not behavior. They're implementation details. "Verifying communications between classes is akin to trying to derive a person's behavior by measuring the signals that neurons in the brain pass among each other."

Mocks verify behavior **only** when they verify interactions that:

1. Cross the application boundary, **and**
2. Produce side effects visible to the external world

## Why Khorikov Prefers Classical (Revisited)

The London school doesn't differentiate intra-system from inter-system communications. It mocks all mutable dependencies. This indiscriminate use of mocks produces tests that couple to implementation details and lack resistance to refactoring.

The classical school is better but still not ideal. It substitutes all shared (out-of-process) dependencies, including application databases that should be treated as part of the system.

Khorikov's position: mock **only unmanaged** out-of-process dependencies (those visible to external clients). Use real instances for everything else, including the application database (covered in integration testing, Ch 8-10).
