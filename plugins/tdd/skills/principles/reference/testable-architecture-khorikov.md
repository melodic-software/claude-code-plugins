# Refactoring Toward Valuable Unit Tests (Khorikov)

Four types of code (2x2 matrix), the Humble Object pattern, code depth vs width, the CRM 4-take refactoring, CanExecute/Execute, domain events, and the three-way trade-off between testability, simplicity, and performance (Ch 7). The central chapter for *writing* valuable tests (vs Ch 4 which covers *recognizing* them).

## The Four Types of Code (2x2 Matrix)

All production code can be categorized along two dimensions:

1. **Complexity or domain significance** — the number of decision-making (branching) points, including implicit ones in libraries. Domain significance = how directly connected to the problem domain
2. **Number of collaborators** — mutable or out-of-process dependencies that must be set up in tests. Immutable dependencies (values, value objects) don't count

```
                        Few collaborators    Many collaborators
                       ┌────────────────────┬────────────────────┐
  High complexity /    │  Domain model,     │  Overcomplicated   │
  domain significance  │  algorithms        │  code              │
                       │  ★ UNIT TEST THIS  │  ✗ SPLIT THIS      │
                       ├────────────────────┼────────────────────┤
  Low complexity /     │  Trivial code      │  Controllers       │
  domain significance  │  ✗ DON'T TEST      │  integration test  │
                       └────────────────────┴────────────────────┘
```

**Where to invest unit testing effort:**

- **Domain model and algorithms** (top-left) — best return on investment. Tests are highly valuable (complex/important logic) AND cheap (few collaborators = low maintenance). *This is what you should unit test*
- **Trivial code** (bottom-left) — constructors, one-line properties. Tests have close-to-zero value. Don't test
- **Controllers** (bottom-right) — coordinate work between domain classes and external systems. Test briefly as part of integration tests (Ch 8-10), not unit tests
- **Overcomplicated code** (top-right) — high on both dimensions. *Fat controllers* that do complex work AND coordinate many dependencies. **Split into algorithms + controllers** using the Humble Object pattern

> "The more important or complex the code, the fewer collaborators it should have."
>
> "It's better to not write a test at all than to write a bad test."

## The Humble Object Pattern

Extract testable logic out of hard-to-test code. The remaining code becomes a thin, *humble* wrapper — it glues the hard-to-test dependency and the extracted logic together, but itself contains little or no logic and doesn't need testing.

Both hexagonal and functional architectures implement this pattern:

- **Hexagonal architecture**: domain layer (logic, testable) + application services layer (orchestration, humble)
- **Functional architecture**: functional core (immutable logic, testable) + mutable shell (side effects, humble)

The functional core has *no* collaborators (all dependencies are values), placing it on the vertical axis. The domain layer in hexagonal architecture has *few* in-process collaborators, placing it in the top-left quadrant.

### Code Depth vs Code Width

> "Your code can be either deep (complex or important) or wide (work with many collaborators), but never both."

Controllers orchestrate many dependencies (wide, many arrows) but aren't complex on their own (shallow blocks). Domain classes are the opposite: complex logic (tall blocks) but few external connections. Visualize it as tall-narrow vs short-wide blocks.

This maps to well-known patterns: MVP, MVC, DDD Aggregates — all separate complex logic from orchestration. The Presenter/Controller/Application Service is the humble object.

## The CRM 4-Take Refactoring

A CRM system with a `User.ChangeEmail()` method demonstrates progressive refactoring from overcomplicated code to cleanly separated concerns.

### Initial State (Overcomplicated)

`User` directly calls `Database` and `MessageBus` — static out-of-process dependencies. High domain significance (email change logic) AND high collaborator count (database + message bus). Falls in the overcomplicated quadrant.

```csharp
// BEFORE — overcomplicated: business logic + out-of-process deps mixed
public void ChangeEmail(int userId, string newEmail)
{
    object[] data = Database.GetUserById(userId);
    // ... business logic interleaved with Database and MessageBus calls ...
    Database.SaveUser(this);
    MessageBus.SendEmailChangedMessage(UserId, newEmail);
}
```

### Take 1: Make Implicit Dependencies Explicit

Introduce interfaces for `Database` and `MessageBus`, inject them. **Not enough** — from the types-of-code perspective, interfaces behind out-of-process dependencies are still out-of-process. Tests still need complicated mock machinery.

> "It doesn't matter if the domain model refers to out-of-process dependencies directly or via an interface. Such dependencies are still *out-of-process*."

### Take 2: Introduce Application Services Layer

Move all out-of-process communication to a `UserController` (application service). `User` no longer touches `Database` or `MessageBus` — zero collaborators, moves to the domain model quadrant.

**Problem**: the controller now contains reconstruction logic (mapping raw `object[]` data to domain objects) and returns the updated employee count from `User.ChangeEmail()` — a misplaced responsibility.

### Take 3: Remove Complexity from the Application Service

Extract reconstruction logic into `UserFactory` and `CompanyFactory`. The controller is now firmly in the controllers quadrant — pure orchestration, no domain logic.

### Take 4: Introduce a Company Class

The awkwardness of returning an updated number of employees reveals a missing abstraction. Introduce `Company` as a domain class with `ChangeNumberOfEmployees()` and `IsEmailCorporate()` methods.

```csharp
// AFTER — clean separation
public class User
{
    public void ChangeEmail(string newEmail, Company company)
    {
        if (Email == newEmail) return;

        UserType newType = company.IsEmailCorporate(newEmail)
            ? UserType.Employee : UserType.Customer;

        if (Type != newType)
        {
            int delta = newType == UserType.Employee ? 1 : -1;
            company.ChangeNumberOfEmployees(delta);
        }

        Email = newEmail;
        Type = newType;
    }
}

// Controller — pure orchestration, no business logic
public class UserController
{
    public void ChangeEmail(int userId, string newEmail)
    {
        object[] userData = _database.GetUserById(userId);
        User user = UserFactory.Create(userData);

        object[] companyData = _database.GetCompany();
        Company company = CompanyFactory.Create(companyData);

        user.ChangeEmail(newEmail, company);

        _database.SaveCompany(company);
        _database.SaveUser(user);
        _messageBus.SendEmailChangedMessage(userId, newEmail);
    }
}
```

`Company`'s methods follow the **Tell Don't Ask** principle — `User` *tells* `Company` to change its employee count rather than asking for raw data and doing it itself.

### Final Types-of-Code Placement

| Quadrant | Few collaborators | Many collaborators |
|----------|------------------|--------------------|
| **High complexity/significance** | `User.ChangeEmail`, `Company.ChangeNumberOfEmployees`, `Company.IsEmailCorporate`, `UserFactory`, `CompanyFactory` | *(empty — goal achieved)* |
| **Low complexity/significance** | Constructors in `User` and `Company` | `UserController.ChangeEmail` |

## Testing After Refactoring

### Domain Layer (Unit Test)

High-value, low-cost tests — output-based and state-based on in-memory objects:

```csharp
[Fact]
public void Changing_email_from_non_corporate_to_corporate()
{
    var company = new Company("mycorp.com", 1);
    var sut = new User(1, "user@gmail.com", UserType.Customer);

    sut.ChangeEmail("new@mycorp.com", company);

    Assert.Equal(2, company.NumberOfEmployees);
    Assert.Equal("new@mycorp.com", sut.Email);
    Assert.Equal(UserType.Employee, sut.Type);
}
```

Four tests cover all branches. Parameterized tests work well for simpler classes like `Company.IsEmailCorporate`.

### Trivial Code (Don't Test)

Constructors with no logic — tests would provide close-to-zero value.

### Preconditions

Test preconditions that have **domain significance** (e.g., `Company.ChangeNumberOfEmployees` requiring non-negative result). Don't test preconditions that are merely technical safeguards without domain meaning (e.g., `UserFactory.Create` requiring array length >= 3).

### Controllers (Integration Test)

Covered in Ch 8-10, not unit tested directly.

## The Three-Way Trade-Off

When business logic needs intermediate data from out-of-process dependencies (can't push all reads/writes to edges), three attributes compete — you can only have two:

```
         Controller simplicity
              ╱        ╲
             ╱          ╲
  Domain model          Performance
  testability ─────────
```

**Option 1: Push all external reads/writes to edges**

- Gets: controller simplicity + domain model testability
- Loses: **performance** (unnecessary I/O calls)

**Option 2: Inject out-of-process dependencies into domain model**

- Gets: controller simplicity + performance
- Loses: **domain model testability** (back to overcomplicated code)

**Option 3: Split decision-making into granular steps**

- Gets: domain model testability + performance
- Loses: **controller simplicity** (controller gets decision-making points)

> Khorikov recommends Option 3 in most cases — performance matters, and overcomplicated domain models (Option 2) are what we refactored away from. Two patterns mitigate the controller complexity cost:

## CanExecute/Execute Pattern

Prevents business logic from leaking into controllers when splitting decisions into steps. The domain model exposes a `CanExecute` method that the controller calls first — the `Execute` method has a precondition requiring `CanExecute` to pass.

```csharp
// Domain model — all validation encapsulated
public string CanChangeEmail()
{
    if (IsEmailConfirmed)
        return "Can't change a confirmed email";
    return null;
}

public void ChangeEmail(string newEmail, Company company)
{
    Precondition.Requires(CanChangeEmail() == null);
    // ... the rest of the method
}

// Controller — no business knowledge needed
string error = user.CanChangeEmail();
if (error != null)
    return error;
// ... proceed with change
```

Benefits:

- Controller doesn't need to know *anything* about email change rules — just calls `CanChangeEmail()`
- The precondition in `ChangeEmail()` guarantees the method is never called without validation
- Multiple validations consolidate into the `CanExecute` method — extensible without touching the controller

> "For simplicity's sake, I'm using a `string` to denote an error. In a real-world project, you may want to introduce a custom `Result` class."

## Domain Events

Track important changes in the domain model and convert them to out-of-process calls *after* the business operation completes. Prevents the controller from needing to decide *when* to notify external systems.

> **"A domain event describes an event in the application that is meaningful to domain experts."** Domain events should always be named in the past tense because they represent things that already happened. They are values — immutable and interchangeable.

```csharp
public class EmailChangedEvent
{
    public int UserId { get; }
    public string NewEmail { get; }
}

// User adds event only when email actually changes
public void ChangeEmail(string newEmail, Company company)
{
    Precondition.Requires(CanChangeEmail() == null);
    if (Email == newEmail) return;
    // ... business logic ...
    EmailChangedEvents.Add(
        new EmailChangedEvent(UserId, newEmail));
}

// Controller processes events after the fact
foreach (var ev in user.EmailChangedEvents)
{
    _messageBus.SendEmailChangedMessage(ev.UserId, ev.NewEmail);
}
```

This solves the notification bug (sending messages when email didn't change) by making the domain model responsible for *when* events are generated. Tests verify domain event creation directly — no mocks needed:

```csharp
sut.EmailChangedEvents.Should().Equal(
    new EmailChangedEvent(1, "new@gmail.com"));
```

> "Domain events remove the decision-making responsibility from the controller and put that responsibility into the domain model, thus simplifying unit testing communications with external systems."

## Observable Behavior as Onion Layers

> "Think of the observable behavior and implementation details as onion layers. Test each layer from the outer layer's point of view, and disregard how that layer talks to the underlying layers."

The external client cares about the controller's `ChangeEmail` method and the message bus call. The controller (as client of `User`) cares about `User.ChangeEmail` — but calls from `User` to `Company` are implementation details from the controller's perspective.

**Rule**: don't verify interactions between domain classes. Only the first call from a controller to a domain class has an immediate connection to the controller's goal. Subsequent inter-domain calls are implementation details.

## Key Principle

> "It's easier to test abstractions than the things they abstract."

- Domain events abstract upcoming messages on the bus
- Changes in domain classes abstract upcoming database modifications
- Both can be tested with plain unit tests — no out-of-process dependencies needed

The goal is to keep all side effects in memory until the very end of the business operation. The controller then materializes them. This lets you test business logic without involving out-of-process dependencies, using output-based and state-based testing on in-memory objects.
