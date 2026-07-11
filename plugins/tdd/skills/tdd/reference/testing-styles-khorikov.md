# Styles of Unit Testing (Khorikov)

Three unit testing styles — output-based, state-based, communication-based — evaluated against the Four Pillars, plus functional programming as a technique to maximize output-based tests (Ch 6). Builds on the Four Pillars framework (Ch 4) and mock/stub taxonomy (Ch 5).

## The Three Styles Defined

### Output-Based Testing (Functional)

Feed an input to the SUT and check the output it produces. Only applicable to code that doesn't change global or internal state — the only result is the return value.

```csharp
// SUT — a mathematical function (no side effects)
public class PriceEngine
{
    public decimal CalculateDiscount(params Product[] products)
    {
        decimal discount = products.Length * 0.01m;
        return Math.Min(discount, 0.2m);
    }
}

// Test — pure input/output verification
[Fact]
public void Discount_of_two_products()
{
    var product1 = new Product("Hand wash");
    var product2 = new Product("Shampoo");
    var sut = new PriceEngine();

    decimal discount = sut.CalculateDiscount(product1, product2);

    Assert.Equal(0.02m, discount);
}
```

Also known as *functional* testing because it roots in functional programming's preference for side-effect-free code.

### State-Based Testing

Verify the state of the system after an operation completes. "State" can refer to the SUT itself, one of its collaborators, or an out-of-process dependency (database, filesystem).

```csharp
public class Order
{
    private readonly List<Product> _products = new List<Product>();
    public IReadOnlyList<Product> Products => _products.ToList();

    public void AddProduct(Product product)
    {
        _products.Add(product);
    }
}

[Fact]
public void Adding_a_product_to_an_order()
{
    var product = new Product("Hand wash");
    var sut = new Order();

    sut.AddProduct(product);

    Assert.Equal(1, sut.Products.Count);
    Assert.Equal(product, sut.Products[0]);
}
```

State-based assertion parts tend to be larger — even this simplified test has four assertion lines. Mitigations: helper methods, value objects with equality comparison (via Fluent Assertions' `BeEquivalentTo`), but both are only occasionally applicable.

### Communication-Based Testing

Uses mocks to verify interactions between the SUT and its collaborators.

```csharp
[Fact]
public void Sending_a_greetings_email()
{
    var emailGatewayMock = new Mock<IEmailGateway>();
    var sut = new Controller(emailGatewayMock.Object);

    sut.GreetUser("user@email.com");

    emailGatewayMock.Verify(
        x => x.SendGreetingsEmail("user@email.com"),
        Times.Once);
}
```

> "The classical school of unit testing prefers the state-based style over the communication-based one. The London school makes the opposite choice. Both schools use output-based testing."

## Comparing the Styles (Four Pillars)

All three styles score equally on **protection against regressions** and **fast feedback** — these depend on how much code executes and whether tests touch out-of-process dependencies, not on style.

The distinguishing metrics are **resistance to refactoring** and **maintainability**:

| Metric | Output-based | State-based | Communication-based |
|--------|-------------|-------------|---------------------|
| Due diligence for resistance to refactoring | Low | Medium | Medium |
| Maintainability costs | Low | Medium | High |

### Resistance to Refactoring

- **Output-based**: best protection against false positives — tests couple only to the method's return value. The only way to couple to implementation details is if the method under test is itself an implementation detail
- **State-based**: more prone to false positives — tests work with the class's state, which is a larger API surface. Greater coupling = higher chance of tying to a leaking implementation detail
- **Communication-based**: most vulnerable — "the vast majority of tests that check interactions with test doubles end up being brittle." Legitimate only when verifying interactions that cross the application boundary with externally visible side effects

### Maintainability

Two characteristics: (1) how hard it is to understand the test (function of size), (2) how hard it is to run the test (function of out-of-process dependencies).

- **Output-based**: almost always short and concise — supply input, verify output. No global/internal state changes, no out-of-process dependencies. Best on both characteristics
- **State-based**: normally less maintainable — state verification takes more space. Even simplified state-based tests have multi-line assertion sections that grow with object complexity
- **Communication-based**: worst on maintainability — requires setting up test doubles, interaction assertions, and often *mock chains* (mocks returning mocks, several layers deep)

### The Verdict

> "Always prefer output-based testing over everything else. Unfortunately, it's easier said than done. This style of unit testing is only applicable to code that is written in a functional way."

## Functional Programming and Output-Based Testing

### Mathematical Functions (Pure Functions)

A *mathematical function* (pure function) has no hidden inputs or outputs. All inputs and outputs are explicitly expressed in the method signature. It produces the same output for a given input regardless of how many times it's called.

**Test for purity — referential transparency**: can you replace a call to the method with its return value without changing the program's behavior?

```csharp
// Mathematical function — referentially transparent
public int Increment(int x) { return x + 1; }
// int y = Increment(4); is equivalent to int y = 5;

// NOT a mathematical function — hidden output (side effect)
int x = 0;
public int Increment() { x++; return x; }
// Can't replace call with return value — side effect changes x
```

### Hidden Inputs and Outputs

Types that break mathematical function status:

- **Side effects** (hidden output) — mutating class state, writing files, updating databases
- **Exceptions** (hidden output) — creating an alternate return path not in the method signature
- **Reference to internal/external state** (hidden input) — `DateTime.Now`, database queries, private mutable fields

> "Explicit inputs and outputs make mathematical functions extremely testable because the resulting tests are short, simple, and easy to understand and maintain. Mathematical functions are the only type of methods where you can apply output-based testing."

### What Is Functional Architecture?

The goal of functional programming is not to eliminate side effects but to *separate* business logic from code that incurs side effects:

> **"Functional architecture maximizes the amount of code written in a purely functional (immutable) way, while minimizing code that deals with side effects."**

This separation creates two types of code:

1. **Functional core (immutable core)** — makes decisions using mathematical functions. No side effects
2. **Mutable shell** — gathers inputs, feeds them to the functional core, converts the core's decisions into side effects (database writes, file I/O, messages)

The cooperation pattern:

1. The mutable shell gathers all the inputs
2. The functional core generates decisions
3. The shell converts the decisions into side effects

> "The goal is to cover the functional core extensively with output-based tests and leave the mutable shell to a much smaller number of integration tests."

### Functional vs Hexagonal Architecture

Both share separation of concerns and one-way dependency flow. The key difference:

- **Hexagonal architecture** allows side effects in the domain layer, as long as modifications stay within the domain layer's boundary (e.g., a domain entity can change its own state, but can't persist to the database directly)
- **Functional architecture** pushes *all* side effects out of the immutable core to the edges of the business operation

> "Functional architecture is a subset of the hexagonal architecture. You can view functional architecture as the hexagonal architecture taken to an extreme."

Michael Feathers' quote captures the distinction:

> "Object-oriented programming makes code understandable by encapsulating moving parts. Functional programming makes code understandable by minimizing moving parts."

## The Audit System Refactoring (3-Stage Example)

An audit system that tracks visitors in text files demonstrates the progression from untestable code to fully output-based testing.

### Stage 1: Initial Implementation (Tightly Coupled)

`AuditManager` directly reads/writes the filesystem via `Directory.GetFiles()` and `File.WriteAllText()`. Tests must work with actual files — shared dependency makes them slow, non-parallelizable, and hard to maintain.

| Pillar | Score |
|--------|-------|
| Protection against regressions | Good |
| Resistance to refactoring | Good |
| Fast feedback | **Bad** |
| Maintainability | **Bad** |

### Stage 2: With Mocks (IFileSystem Interface)

Extract filesystem operations behind `IFileSystem` interface, inject via constructor. Tests mock the interface — no real filesystem needed.

```csharp
// Test uses mock to verify file write
fileSystemMock.Verify(x => x.WriteAllText(
    @"audits\audit_3.txt",
    "Alice;2019-04-06T18:00:00"));
```

Improvement: fast feedback restored, maintainability improved. But mock setups are convoluted — tests are less readable than pure input/output.

| Pillar | Score |
|--------|-------|
| Protection against regressions | Good |
| Resistance to refactoring | Good |
| Fast feedback | Good |
| Maintainability | **Moderate** |

### Stage 3: Functional Architecture (No Mocks)

Move side effects *out of* `AuditManager` entirely. It becomes a functional core that accepts `FileContent[]` (inputs as values) and returns `FileUpdate` (decisions as values). A new `Persister` class (mutable shell) handles actual filesystem I/O. An `ApplicationService` glues them together.

```csharp
// Functional core — pure function, no side effects
public class AuditManager
{
    public FileUpdate AddRecord(
        FileContent[] files,
        string visitorName,
        DateTime timeOfVisit)
    {
        // ... sorting, decision logic ...
        return new FileUpdate("audit_3.txt", newRecord);
    }
}

// Mutable shell — trivial, no branching (no if statements)
public class Persister
{
    public FileContent[] ReadDirectory(string directoryName) { ... }
    public void ApplyUpdate(string directoryName, FileUpdate update) { ... }
}

// Application service — orchestration glue
public class ApplicationService
{
    public void AddRecord(string visitorName, DateTime timeOfVisit)
    {
        FileContent[] files = _persister.ReadDirectory(_directoryName);
        FileUpdate update = _auditManager.AddRecord(
            files, visitorName, timeOfVisit);
        _persister.ApplyUpdate(_directoryName, update);
    }
}
```

The test becomes pure input/output with plain values — no mocks, no filesystem:

```csharp
[Fact]
public void A_new_file_is_created_when_the_current_file_overflows()
{
    var sut = new AuditManager(3);
    var files = new FileContent[]
    {
        new FileContent("audit_1.txt", new string[0]),
        new FileContent("audit_2.txt", new string[]
        {
            "Peter; 2019-04-06T16:30:00",
            "Jane; 2019-04-06T16:40:00",
            "Jack; 2019-04-06T17:00:00"
        })
    };

    FileUpdate update = sut.AddRecord(
        files, "Alice", DateTime.Parse("2019-04-06T18:00:00"));

    Assert.Equal("audit_3.txt", update.FileName);
    Assert.Equal("Alice;2019-04-06T18:00:00", update.NewContent);
}
```

| Pillar | Score |
|--------|-------|
| Protection against regressions | Good |
| Resistance to refactoring | Good |
| Fast feedback | Good |
| Maintainability | **Good** |

### Key Insight: Values, Not Collaborators

The functional core's output (`FileUpdate`) is a *value* (or set of values) — two instances are interchangeable if their contents match. Convert to `struct` or define custom equality for even cleaner assertions:

```csharp
Assert.Equal(
    new FileUpdate("audit_3.txt", "Alice;2019-04-06T18:00:00"),
    update);
```

> "A class from the functional core should work not with a collaborator, but with the product of its work, a value."

### Extensibility of the Pattern

More complex use cases still fit the pattern:

- **Multiple operations** (e.g., `DeleteAllMentions`) — return `FileUpdate[]` instead of `FileUpdate`
- **Delete operations** — rename `FileUpdate` to `FileAction` with an `ActionType` enum
- **Error handling** — embed errors in the return type: `public (FileUpdate update, Error error) AddRecord(...)` — the application service checks for errors and skips the persister call

## Drawbacks of Functional Architecture

### Applicability Limits

Functional architecture works when the system can gather all inputs upfront, before making a decision. When intermediate decisions require additional data from out-of-process dependencies, the pattern breaks:

```csharp
// This BREAKS functional architecture — IDatabase is a hidden input
public FileUpdate AddRecord(
    FileContent[] files, string visitorName,
    DateTime timeOfVisit, IDatabase database)
```

Two workarounds when intermediate dependencies are needed:

1. **Gather everything upfront** in the application service — preserves functional core separation but wastes performance (unconditional queries even when not needed)
2. **Introduce a check method** (`IsAccessLevelCheckRequired()`) — the service calls it first, conditionally queries the database, then passes the result as a value. Preserves decision-making in the core but leaks some decision responsibility to the service

Neither option is perfect — this is the applicability limit of functional architecture.

### Performance Drawbacks

The read-decide-act approach requires more calls to out-of-process dependencies than the initial tightly-coupled version (which read lazily). It's not that *tests* get slower — output-based tests are faster. The *system itself* makes more I/O calls.

> "The choice between a functional architecture and a more traditional one is a trade-off between performance and code maintainability (both production and test code). In some systems where the performance impact is not as noticeable, it's better to go with functional architecture for additional gains in maintainability. In others, you might need to make the opposite choice. There's no one-size-fits-all solution."

### Increase in Code Base Size

Functional architecture introduces additional classes and indirection (the `Persister`, `FileContent`, `FileUpdate`, `ApplicationService` in our example vs just `AuditManager` in the original). The initial tightly-coupled version was one class; the functional version is four.

This cost is justified when the domain model's complexity warrants it. For simple CRUD operations with little business logic, functional architecture adds overhead without proportionate benefit.

## Decision Framework

```
Can the SUT be written as a mathematical function?
  ├── Yes → OUTPUT-BASED testing (always prefer this)
  │         Functional core + mutable shell pattern
  │
  └── No → Does the SUT's outcome manifest as state change?
            ├── Yes → STATE-BASED testing (second choice)
            │         Use helper methods/value objects for assertion clarity
            │
            └── No → COMMUNICATION-BASED testing (last resort)
                      Only for inter-system communications with
                      externally visible side effects
```

The right strategy is not to pick one style, but to refactor production code toward functional architecture so more tests become output-based.
