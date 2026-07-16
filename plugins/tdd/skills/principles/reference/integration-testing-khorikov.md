# Integration Testing, Mocking Best Practices, and Database Testing (Khorikov)

Integration test role, managed vs unmanaged dependencies, the Test Pyramid revisited, Fail Fast principle, interfaces (only for unmanaged deps), logging testing (support vs diagnostic, DomainLogger), five mocking best practices, and database testing (migrations, transactions, UoW, avoid in-memory DBs, clean at start) (Ch 8-10). The practical application of everything from Part 2.

## What Is an Integration Test?

An integration test is any test that is not a unit test — it fails at least one of the three unit test requirements:

1. Verifies a single unit of behavior
2. Does it quickly
3. Does it in isolation from other tests

In practice, integration tests verify how your system works with out-of-process dependencies. They cover code from the **controllers quadrant** (Ch 7's 2x2 matrix), while unit tests cover the domain model and algorithms quadrant.

## The Test Pyramid Revisited

```
        /  E2E  \          ↑ Protection against regressions,
       /----------\           resistance to refactoring
      / Integration \
     /----------------\     ↓ Fast feedback,
    /    Unit tests     \     maintainability
```

- **Unit tests**: fast, cheap, cover edge cases in business logic
- **Integration tests**: slower, more expensive, cover the happy path + edge cases that unit tests can't reach
- **End-to-end tests**: optional 1-2 overarching sanity checks post-deployment

**Guideline**: check as many edge cases as possible with unit tests. Use integration tests to cover **one longest happy path per business scenario** (touching all out-of-process dependencies) and any edge cases that can't be covered by unit tests.

**Simple projects** may have equal numbers of unit and integration tests (rectangle instead of pyramid) because they have little domain logic. Integration tests retain value even in simple projects.

### Integration Testing vs Fail Fast

Not every edge case needs an integration test. If an incorrect execution of an edge case crashes the application immediately (fail fast), there's no need for a test — the bug is self-revealing and doesn't lead to data corruption.

> **The Fail Fast principle** stands for stopping the current operation as soon as any unexpected error occurs. Benefits: shortens the feedback loop, protects the persistence state from corruption. Preconditions are a primary example.

## Managed vs Unmanaged Dependencies

All out-of-process dependencies fall into two categories:

| | Managed | Unmanaged |
|---|---------|-----------|
| **Access** | Only your application | Other applications too |
| **Visibility** | Not observable externally | Observable externally |
| **Example** | Application database | SMTP server, message bus |
| **In tests** | Use real instance | Replace with mock |
| **Communications are** | Implementation details | Observable behavior (contract) |

> **"Use real instances of managed dependencies; replace unmanaged dependencies with mocks."**

### Mixed Dependencies

Sometimes a dependency is both managed and unmanaged — e.g., a database where some tables are shared with other applications. Treat the shared tables as unmanaged (mock them), treat the rest as managed (test directly). A shared database is a poor integration mechanism — prefer APIs or message buses.

### When You Can't Use a Real Database

If you can't test with a real database instance, don't mock it — mocking a managed dependency compromises resistance to refactoring. Instead, skip integration tests entirely and focus on unit testing the domain model. Tests that don't provide high value should not exist.

## Interfaces: When and Why

### Interfaces with a Single Implementation Are Not Abstractions

> "Genuine abstractions are *discovered*, not *invented*. The discovery, by definition, takes place post factum, when the abstraction already exists but is not yet clearly defined in the code."

Two common misconceptions about interfaces:

1. "They achieve loose coupling" — False. An interface with a single implementation provides no more loose coupling than the concrete class itself
2. "They enable the Open-Closed Principle" — This violates YAGNI. Don't anticipate future implementations

### The Only Legitimate Reason: Mocking

> **"Don't introduce interfaces for out-of-process dependencies unless you need to mock out those dependencies."** Use interfaces for unmanaged dependencies only. Use concrete classes for managed dependencies.

```csharp
public class UserController
{
    private readonly Database _database;         // Concrete — managed dep
    private readonly IMessageBus _messageBus;    // Interface — unmanaged dep
}
```

### Never Use Interfaces for In-Process Dependencies

Interfaces on domain classes (e.g., `IUser`) are a red flag — they hint at using mocks to check interactions between domain classes, which couples tests to implementation details.

## Logging Testing

### Support Logging vs Diagnostic Logging

Two types (from Freeman & Pryce, *Growing Object-Oriented Software*):

- **Support logging** — for support staff and system administrators. Part of the application's **observable behavior**. Must be tested
- **Diagnostic logging** — for developers. An **implementation detail**. Don't test

### The DomainLogger Pattern

Don't mock raw `ILogger` for support logging — create a `DomainLogger` (implements `IDomainLogger`) that declares specific business-meaningful log operations:

```csharp
public class DomainLogger : IDomainLogger
{
    private readonly ILogger _logger;

    public void UserTypeHasChanged(
        int userId, UserType oldType, UserType newType)
    {
        _logger.Info(
            $"User {userId} changed type from {oldType} to {newType}");
    }
}
```

When `DomainLogger` introduces an out-of-process dependency into domain classes, use **domain events** (e.g., `UserTypeChangedEvent`) to keep the domain model clean — the controller dispatches events to `DomainLogger` after the business operation.

### Logging Guidelines

- Support logging amount is a business decision — always test it
- Diagnostic logging: use sparingly, ideally only for unhandled exceptions. Excessive logging clutters code and damages signal-to-noise ratio
- Never use ambient context (static `LogManager.GetLogger()`) — always inject loggers explicitly via constructor or method parameter
- `IDomainLogger` can stay at the `IDomainLogger` level for mocking (unlike `IMessageBus` which should be mocked at `IBus`) — the exact log text structure matters less than message bus contracts

## Five Mocking Best Practices

### 1. Mock Only Unmanaged Dependencies

> "Applying mocks to unmanaged dependencies only" — the foundational rule. Using mocks for anything else results in brittle tests.

### 2. Verify Interactions at the System's Edges

Mock the **last type** in the chain between your controller and the unmanaged dependency. For a message bus: mock `IBus` (the raw transport), not `IMessageBus` (your domain-specific wrapper).

```csharp
// BAD — mocking an intermediate type
messageBusMock.Verify(x => x.SendEmailChangedMessage(
    user.UserId, "new@gmail.com"), Times.Once);

// GOOD — mocking at the system edge (IBus)
busMock.Verify(x => x.Send(
    "Type: USER EMAIL CHANGED; " +
    $"Id: {user.UserId}; " +
    "NewEmail: new@gmail.com"), Times.Once);
```

This maximizes both protection against regressions (more code exercised) and resistance to refactoring (tests verify the actual external contract, not internal class structure).

> "Don't rely on the production code when making assertions. Use a separate set of literals and constants in tests."

### 3. Use Mocks in Integration Tests Only, Not Unit Tests

Mocks are for unmanaged dependencies. Controllers are the only code working with unmanaged dependencies. Tests on controllers are integration tests. Therefore: mocks belong only in integration tests.

### 4. Not Just One Mock Per Test

The "one mock per test" guideline is a misconception rooted in the London school's "unit = class" error. The number of mocks depends on the number of unmanaged dependencies in the operation. Multiple mocks per test is fine.

### 5. Verify the Number of Calls

Verify both:

- **Existence** of expected calls (`Times.Once`)
- **Absence** of unexpected calls (`VerifyNoOtherCalls()`)

This ensures backward compatibility in both directions — no missing messages AND no extra messages.

### Spies Are Superior to Mocks at System Edges

Spies (handwritten mocks) provide reusable fluent assertion interfaces:

```csharp
public class BusSpy : IBus
{
    private List<string> _sentMessages = new List<string>();

    public void Send(string message) { _sentMessages.Add(message); }

    public BusSpy ShouldSendNumberOfMessages(int number)
    {
        Assert.Equal(number, _sentMessages.Count);
        return this;
    }

    public BusSpy WithEmailChangedMessage(int userId, string newEmail)
    {
        string message = "Type: USER EMAIL CHANGED; " + ...;
        Assert.Contains(_sentMessages, x => x == message);
        return this;
    }
}

// Usage — fluent, readable assertions
busSpy.ShouldSendNumberOfMessages(1)
    .WithEmailChangedMessage(user.UserId, "new@gmail.com");
```

`ShouldSendNumberOfMessages(1)` encompasses both `Times.Once` and `VerifyNoOtherCalls()`. The spy provides an independent checkpoint — it doesn't trust production code for assertion values.

## Database Testing Prerequisites

### 1. Keep the Database Schema in Source Control

Treat the database schema as regular code. No "model database" instances — they have no change history and create a competing source of truth.

**Reference data** (data required for the application to operate, like `UserType` lookup tables) is part of the schema — store it as SQL INSERT statements alongside table definitions.

> "If your application can modify the data, it's regular data; if not, it's reference data."

### 2. Separate Instance per Developer

Never share a test database. Tests interfere with each other, and non-backward-compatible changes block other developers.

### 3. Migration-Based Over State-Based Delivery

| | State-based | Migration-based |
|---|-------------|-----------------|
| **Explicit** | State (SQL scripts) | Migrations (transition scripts) |
| **Implicit** | Migrations (comparison tool) | State (assemble from migrations) |
| **Better at** | Merge conflicts | Data motion |

**Prefer migration-based** — data motion (transforming existing data to match new schema) is much more important than merge conflict resolution. Comparison tools can't make reliable domain-specific assumptions about data transformations.

> "Apply every modification to the database schema (including reference data) through migrations. Don't modify migrations once committed. Create a new migration to fix errors."

## Database Testing Best Practices

### Transaction Management

Split the `Database` class into:

- **Repositories** — access and modify data (short-lived)
- **Transaction / Unit of Work** — commits or rolls back all changes atomically (lives for the entire business operation)

The `Transaction` class uses `Commit()` + `Dispose()` — `Commit()` marks the transaction as successful, `Dispose()` ends it (persisting if committed, rolling back otherwise). This guarantees the database is only altered during happy paths. Repositories accept `Transaction` as a constructor parameter, so they always work on top of transactions and can never call the database independently.

**Upgrading Transaction to Unit of Work:** A unit of work maintains a list of objects affected by a business operation and executes all updates as a single unit at the end. The key advantage over a plain transaction is the *deferral of updates* — all changes execute at the end of the business operation, minimizing database transaction duration and reducing data congestion.

ORMs like Entity Framework implement the Unit of Work pattern natively. In Listing 10.4, `CrmContext` (inheriting `DbContext`) replaces `Transaction` directly:

- Repositories work on top of `CrmContext` just as they worked on top of `Transaction`
- The controller commits via `context.SaveChanges()` instead of `transaction.Commit()`
- `UserFactory` and `CompanyFactory` are eliminated — EF now serves as the mapper between raw database data and domain objects

This is the key insight: **the ORM IS the mapper**. There's no need for separate factory classes to translate between database rows and domain objects when EF Core handles that mapping through its change tracker and entity configuration.

### Don't Reuse Transactions Between Test Sections

> **"Don't reuse database transactions or units of work between sections of the test."**

Use at least three separate database contexts:

1. **Arrange** — seed data, then `SaveChanges()` and dispose
2. **Act** — create fresh context for the controller (matches production behavior)
3. **Assert** — create fresh context to query and verify independently

Sharing a context between sections creates an environment that doesn't match production (caching, change tracking differences).

### Database Transaction Count Trade-off

After extracting reusable helpers (factory methods for arrange, decorator methods for act, query helpers for assert), a test may use more database contexts than before — e.g., five instead of three. Is this a problem?

The additional database contexts make the test slightly slower, but there's not much that can be done about it. This is a trade-off between fast feedback and maintainability — and **it's worth choosing maintainability**. The performance degradation shouldn't be significant, especially when the database is located on the developer's machine. The gains in readability and maintainability are substantial.

This is a recurring theme: when aspects of a valuable test conflict, prefer maintainability over speed unless the slowdown is dramatic. A test that's easy to understand and maintain at the cost of a few extra milliseconds per database context is better than a faster test coupled to implementation details.

### Avoid In-Memory Databases

> "I don't recommend using in-memory databases because they aren't consistent functionality-wise with regular databases."

In-memory databases (SQLite, EF InMemory) create a mismatch between production and test environments. Tests can produce false positives or false negatives due to differences. Use the **same DBMS** in tests as in production (version/edition can differ).

### Clean Data at the Start, Not the End

Four options for clearing leftover test data:

1. ~~Restore database backup~~ — too slow
2. ~~Clean at end of test~~ — skipped if test crashes
3. ~~Wrap in transaction, never commit~~ — creates inconsistent behavior vs production
4. **Clean at the beginning of each test** — fast, reliable, no skipped cleanup

Implement cleanup in a base class constructor that runs before each test. Write the deletion SQL manually (respecting foreign key order). Delete regular data only — reference data is controlled by migrations.

### Testing Reads vs Writes

The asymmetry between reads and writes is fundamental to database testing strategy:

**Writes — always test thoroughly:**

- Mistakes in write operations lead to data corruption, which can affect not only your database but also external applications that depend on it
- Tests covering writes are highly valuable because the protection they provide is proportional to the stakes

**Reads — higher threshold for testing:**

- A bug in a read operation usually doesn't have consequences as detrimental as a write bug — no data corruption, no side effects propagating to external systems
- Test only the most complex or important read operations; disregard the rest

**Why reads don't need a domain model:** One of the main goals of domain modeling is encapsulation — preserving data consistency in light of changes (Ch 5-6). The lack of data changes makes encapsulation pointless for reads. You don't need a full ORM (NHibernate, Entity Framework) for reads either — plain SQL is superior performance-wise, bypassing unnecessary layers of abstraction.

**Unit tests are useless for reads:** Because there are hardly any abstraction layers in reads (the domain model is one such layer), unit tests have no target. If you decide to test reads, do so using integration tests on a real database — the same approach as for writes, just applied more selectively.

### Don't Test Repositories Independently

> *"Don't test repositories directly, only as part of the overarching integration test suite."*

It might seem beneficial to test how repositories map domain objects to the database — there's significant room for mistakes. But such tests are a net loss due to two compounding drawbacks:

**High maintenance costs:** Repositories fall into the controllers quadrant on the types-of-code diagram (Ch 7) — low complexity, many collaborators. The presence of the database (out-of-process dependency) inflates test maintenance to the same level as regular integration tests. But does testing repositories provide equal benefits? It doesn't.

**Inferior protection against regressions:** Repositories don't carry much complexity, and a lot of the gains in protection against regressions overlap with the gains already provided by regular integration tests. Tests on repositories don't add significant enough value.

**The ideal that ORMs prevent:** The best course of action would be to extract the mapping complexity into self-contained classes (like `UserFactory` and `CompanyFactory`) and test those exclusively — pure algorithms with no out-of-process dependencies. The repositories would then contain only simple SQL queries. Unfortunately, this separation between mapping (factories) and database interaction (repositories) is impossible when using an ORM — you can't test your ORM mappings without calling the database, at least not without compromising resistance to refactoring.

**Same applies to `EventDispatcher`:** Don't test it separately either — it converts domain events into calls to unmanaged dependencies. Too few gains in protection against regressions for the too-high costs of maintaining the complicated mock machinery.

## Integration Test Best Practices

### Make Domain Model Boundaries Explicit

The domain model should have a clear, well-known location (separate assembly/namespace). This makes it easy to distinguish between unit tests (domain model) and integration tests (controllers).

### Reduce the Number of Layers

> "All problems in computer science can be solved by another layer of indirection, except for the problem of too many layers of indirection." — David J. Wheeler

Most backend systems need only three layers:

1. **Domain layer** — business logic
2. **Application services layer** (controllers) — orchestration
3. **Infrastructure layer** — out-of-process dependency access, algorithms not in the domain

### Eliminate Circular Dependencies

Circular dependencies destroy testability and cognitive navigability. Don't mask cycles with interfaces — break them by returning values instead of callbacks.

### Object Mother Pattern for Test Data

Factory methods with default parameters create readable, focused tests:

```csharp
private User CreateUser(
    string email = "user@mycorp.com",
    UserType type = UserType.Employee,
    bool isEmailConfirmed = false)
{
    // ... creates and persists user ...
}

// Usage — only specify what's relevant to the scenario
User user = CreateUser(email: "user@mycorp.com", type: UserType.Employee);
```

Khorikov prefers Object Mother (factory methods with defaults) over Test Data Builder (fluent `.With*()` chains) — less boilerplate in C# thanks to optional parameters.
