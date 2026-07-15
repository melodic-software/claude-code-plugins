# Classical vs London Schools of Unit Testing (Khorikov)

The two schools, their dependency taxonomies, what "isolation" means to each, and why Khorikov prefers classical (Ch 2).

## The Definition of a Unit Test

Three attributes, agreed by both schools:

1. Verifies a small piece of code (a unit)
2. Does it quickly
3. Does it in an **isolated** manner

The first two are non-controversial. The third — what *isolation* means — is the root of all disagreement.

## The Isolation Disagreement

### London School (Mockist)

Isolation = isolate the **system under test from its collaborators**. Replace all dependencies with test doubles so you verify the SUT exclusively, separated from external influence.

```csharp
// London style — Store replaced with a mock
var storeMock = new Mock<IStore>();
storeMock
    .Setup(x => x.HasEnoughInventory(Product.Shampoo, 5))
    .Returns(true);
var customer = new Customer();

bool success = customer.Purchase(storeMock.Object, Product.Shampoo, 5);

Assert.True(success);
storeMock.Verify(
    x => x.RemoveInventory(Product.Shampoo, 5),
    Times.Once);
```

Benefits claimed:

- Know exactly which class broke (no other suspects)
- Split the object graph (don't recreate deep dependency chains)
- Simple structure: one test class per production class

### Classical School (Detroit)

Isolation = isolate **unit tests from each other**. Tests shouldn't share mutable state (databases, static fields) that lets one test affect another's outcome. But using real collaborators within a test is fine.

```csharp
// Classical style — real Store instance, real collaborators
var store = new Store();
store.AddInventory(Product.Shampoo, 10);
var customer = new Customer();

bool success = customer.Purchase(store, Product.Shampoo, 5);

Assert.True(success);
Assert.Equal(5, store.GetInventory(Product.Shampoo));
```

The classical test verifies both `Customer` and `Store` together. A bug in `Store` will fail `Customer`'s tests too — and that's fine.

## The Two Schools Summarized

| | Isolation of | A *unit* is | Uses test doubles for |
|---|---|---|---|
| **London** | Units (SUT from deps) | A class | All but immutable dependencies |
| **Classical** | Unit tests (from each other) | A class or a set of classes | Shared dependencies |

## Dependency Taxonomy

Khorikov defines a precise hierarchy of dependency types. Understanding these is essential — the schools differ primarily in *which* dependencies they replace.

### Core Types

- **Shared dependency** — shared between tests and provides means for tests to affect each other's outcome. Examples: a static mutable field, a database. "A change to such a field is visible across all unit tests running within the same process."
- **Private dependency** — a dependency that is not shared.
- **Out-of-process dependency** — runs outside the application's execution process; a proxy to data not yet in memory. Usually shared, but not always.
- **Volatile dependency** — exhibits one or both: (1) requires runtime environment setup beyond what's installed by default (databases, API services), (2) contains non-deterministic behavior (random number generator, clock).

### Derived Types

- **Value object (value)** — an immutable private dependency, identified solely by its content (no individual identity). Two instances with the same content are interchangeable. Examples: `Product.Shampoo`, the number `5`, any C# enum or struct used as data.
- **Collaborator** — a dependency that is either shared or mutable. "A class providing access to the database is a collaborator since the database is a shared dependency. `Store` is a collaborator too, because its state can change over time."

### The Hierarchy (Figure 2.4)

```
Dependency
├── Shared ←── Classical school replaces these
│                ← London school also replaces these
└── Private
    ├── Mutable (collaborator) ← London school replaces these
    └── Value object (immutable) ← Neither school replaces these
```

### Shared vs Out-of-Process (Figure 2.5)

These overlap but are not identical:

| Example | Shared? | Out-of-process? |
|---------|---------|-----------------|
| Database | Yes | Yes |
| Singleton / static mutable field | Yes | No |
| Read-only API service | No | Yes |

"Not all out-of-process dependencies fall into the category of shared dependencies. A shared dependency almost always resides outside the application's process, but the opposite isn't true." A read-only API is out-of-process but not shared — tests can't mutate its data, so they can't affect each other.

In practice, Khorikov uses *shared dependency* and *out-of-process dependency* interchangeably because "you rarely have a shared dependency that isn't out-of-process" in real-world projects.

## Why Khorikov Prefers Classical

He evaluates each London school selling point:

### 1. "Better granularity" — Misleading

> "Tests shouldn't verify *units of code*. Rather, they should verify *units of behavior*: something that is meaningful for the problem domain and, ideally, something that a business person can recognize as useful."

A unit of behavior may span multiple classes or live in a single method — the number of classes is irrelevant. Finer granularity can actually *damage* tests by making them harder to understand.

The dog analogy:

```
// Good test (unit of behavior)
When I call my dog, he comes right to me.

// Bad test (unit of code — London granularity)
When I call my dog, he moves his front left leg first, then the front
right leg, his head turns, the tail start wagging...
```

"The second story makes much less sense. What's the purpose of all those movements? Is the dog coming to me? Or is he running away? You can't tell."

### 2. "Easier to test interconnected classes" — Hides design problems

"Instead of finding ways to test a large, complicated graph of interconnected classes, you should focus on not having such a graph of classes in the first place. More often than not, a large class graph is a result of a code design problem."

"The use of mocks only hides this problem; it doesn't tackle the root cause."

### 3. "Precise bug location" — Valid but minor

London-style tests point to the exact broken class. Classical tests may cascade — one bug causes many failures. But Khorikov dismisses this concern:

- If you run tests frequently (after each change), you know what caused the bug
- Cascading failures are *useful* — they reveal how much of the system depends on the broken code

### 4. Over-specification — The decisive argument

> "The most crucial distinction between the schools is the issue of over-specification: that is, coupling the tests to the SUT's implementation details. The London style tends to produce tests that couple to the implementation more often than the classical style."

This couples directly to **Pillar 2: Resistance to Refactoring** (Ch 4). Tests that verify interaction patterns (`storeMock.Verify(x => x.RemoveInventory(...), Times.Once)`) break when you refactor how the SUT achieves its result — even if the result is unchanged. This creates false positives.

## Integration Tests in the Two Schools

The schools also disagree on what constitutes an integration test:

- **London**: any test that uses a real collaborator object (not just shared deps) is an integration test
- **Classical**: a test that fails to meet any of the three unit test attributes

Khorikov's classical redefinition of a unit test:

1. Verifies a **single unit of behavior**
2. Does it **quickly**
3. Does it in isolation **from other tests**

An integration test fails one or more of these. A test reaching a database can't run in isolation from other tests (they share the DB), so it's an integration test. End-to-end tests are a subset of integration tests — they just exercise more of the system.

## TDD Approach Differences

- **London** → outside-in TDD: start with high-level tests specifying collaborator interfaces, work inward implementing each class
- **Classical** → inside-out TDD: start from the domain model, add layers on top until the software is usable by the end user

## Key Takeaway

The classical school produces tests that are better aligned with the Four Pillars — particularly Pillar 2 (Resistance to Refactoring) — because they verify *outcomes* (state changes, return values) rather than *interactions* (method calls on collaborators). Khorikov's position throughout the rest of the book builds on this preference.
