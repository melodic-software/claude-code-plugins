# Test Design & Organization

How to write good tests, what to test, xUnit framework patterns, and when to stop testing. Beck (Ch 25, 27, 29, 32) plus Khorikov's AAA refinements, naming guidelines, fixture reuse, and parameterized tests (Ch 3).

## The 3A Pattern (Ch 19, Bill Wake)

Every test has three phases:

1. **Arrange** — Create objects (fixture)
2. **Act** — Stimulate them
3. **Assert** — Check results

Arrange is often shared (setUp); Act and Assert are unique per test.

## Writing the Test

### Assert First (Ch 25)

Start from the assertion and work backward. This forces you to answer "what's the right answer?" and "how do I check?" before everything else.

```java
// Start here:
assertEquals(Money.dollar(10), reduced);

// Then: where does 'reduced' come from?
Money reduced = bank.reduce(sum, "USD");

// Then: where does 'sum' come from?
Expression sum = five.plus(five);

// Then: where does 'five' come from?
Money five = Money.dollar(5);
```

### Test Data (Ch 25)

- Use data that makes tests easy to read — "you are writing tests to an audience"
- If there's a difference in data, it should be meaningful
- Never use the same constant for two purposes: test `3 + 4`, not `2 + 2` (what if args are reversed?)
- Don't use a list of 10 items when 3 leads to the same design decisions

### Evident Data (Ch 25)

Make the relationship between inputs and expected outputs visible in the test itself:

```java
// BAD — where does 49.25 come from?
assertEquals(new Note(49.25, "GBP"), result);

// GOOD — the calculation is visible
bank.addRate("USD", "GBP", 2);
bank.commission(0.015);
assertEquals(new Note(100 / 2 * (1 - 0.015), "GBP"), result);
```

"I can read this test and see the connection between the numbers used in the input and the numbers used to calculate the expected result."

### Child Test (Ch 27)

When a test is too big (requires multiple changes to work), write a smaller test that represents the broken part. Get the small one working, then reintroduce the big one. "Even ten minutes with a red bar gives me the willies."

### One Step Test (Ch 26)

"Pick a test that will teach you something and that you are confident you can implement." Programs grow from **known to unknown** — neither top-down nor bottom-up.

### Starter Test (Ch 26)

Start with a trivially simple variant. For a polygon reducer: input = empty polygon list, output = empty polygon list. "Bing! The first test is running."

## xUnit Patterns (Ch 29)

### Assertion

Be specific: `assertEquals(50, rectangle.area())` not `assertTrue(rectangle.area() != 0)`. Expected value goes first. Test observable behavior, not implementation: don't check `contract.status.class` — check what the status *enables* (like `contract.startDate()`).

"Wishing for white box testing is not a testing problem, it is a design problem."

### Fixture

Common setup code extracted to `setUp()`. Each test gets a fresh instance — no sharing between tests. "If I find myself wanting a slightly different fixture, I start a new subclass of TestCase."

There's no simple 1:1 relationship between test classes and model classes. "Sometimes one fixture serves to test several classes. Sometimes two or three fixtures are needed for a single model class."

### External Fixture

Use `tearDown()` to release external resources (files, connections). xUnit guarantees tearDown runs even if the test fails. Eliminates noisy try/finally in every test.

### Test Method

- Name begins with "test" (convention for auto-discovery)
- Name should tell a future reader WHY the test was written: `testAssertPosInfinityNotEqualsNegInfinity`
- Aim for 3+ lines minimum, straightforward top-to-bottom
- "If a test method is getting long and complicated, play Baby Steps"

### Exception Test

```java
public void testMissingRate() {
    try {
        exchange.findRate("USD", "GBP");
        fail();  // If no exception, test fails
    } catch (IllegalArgumentException expected) {
    }
}
```

Only catch the specific exception you expect.

### All Tests

One suite per package, one aggregating suite for the whole application. "The next time all of the tests run, that test method should run, too."

## What to Test (Ch 32)

"Write tests until fear is transformed into boredom." Test:

- Conditionals
- Loops
- Operations
- Polymorphism

**But only those you write.** Don't test third-party code unless you distrust it. Use Learning Tests (Ch 26) for third-party APIs.

### When to Delete Tests (Ch 32)

Two criteria:

1. **Confidence** — never delete a test if it reduces your confidence
2. **Communication** — if two tests exercise the same path but speak to different scenarios, keep both

"If you have two tests that are redundant with respect to confidence AND communication, delete the least useful."

## Test Quality Signals (Ch 32)

Tests that suggest **design problems** (not test problems):

| Signal | Design problem |
|--------|---------------|
| **Long setup code** | Objects are too big, need splitting |
| **Setup duplication** | Too many objects too tightly intertwined |
| **Long running tests** | Bits and pieces are hard to test in isolation |
| **Fragile tests** | One part surprisingly affects another — hidden coupling |

"The equivalent of 9.8 m/s² is the ten-minute test suite. Suites that take longer than ten minutes inevitably get trimmed."

### Coverage (Ch 17)

- Statement coverage: TDD should yield ~100%. JProbe found only `Money.toString()` uncovered (debugging aid, not model code)
- Defect insertion (Jester): only `Pair.hashCode()` survived — the faked `return 0` implementation
- Two ways to improve coverage: write more tests OR simplify the code. "Refactoring reduces paths to cover"

For Khorikov's deeper treatment of coverage metrics: [code-coverage-khorikov.md](code-coverage-khorikov.md)

## The Fibonacci Example (Appendix II)

A compact TDD demo that "turned on the light" for reviewers. Drives the implementation entirely from tests:

```java
// Test evolves from table-driven data:
int cases[][] = {{0,0}, {1,1}, {2,1}, {3,2}};
for (int i = 0; i < cases.length; i++)
    assertEquals(cases[i][1], fib(cases[i][0]));

// Implementation evolves from constants to recursion:
// Step 1: return 0;
// Step 2: if (n == 0) return 0; return 1;
// Step 3: if (n == 0) return 0; if (n <= 2) return 1; return 2;
// Step 4: ... return 1 + 1;     (2 = 1 + 1)
// Step 5: ... return fib(n-1) + 1;  (first 1 = fib(n-1))
// Step 6: ... return fib(n-1) + fib(n-2);  (second 1 = fib(n-2))
// Step 7: tighten: if (n == 1) return 1;  (== not <=)
// Final:
int fib(int n) {
    if (n == 0) return 0;
    if (n == 1) return 1;
    return fib(n-1) + fib(n-2);
}
```

"There we have Fibonacci, derived totally from the tests." The key move: `return 2` → `return 1 + 1` → `return fib(n-1) + 1` → `return fib(n-1) + fib(n-2)`. Each step replaces a constant with an expression, driven by the data.

---

## Khorikov's AAA Refinements (Ch 3)

### Section Sizing Rules

- **Arrange**: the largest section. If significantly larger than act + assert combined, extract into private factory methods (Object Mother pattern) or a base class
- **Act**: should be a **single line** for unit tests. Two or more lines suggest the SUT's API lacks encapsulation (invariant violation risk). Exception: utility/infrastructure code where multi-step act is acceptable
- **Assert**: multiple assertions are fine — a unit of behavior can have multiple outcomes. But watch for assertion sections that grow too large (sign of a missing value object with equality semantics)

### Avoid `if` Statements in Tests

A test should be a simple, linear sequence — no branching. An `if` in a test means it verifies too many things. Split it into separate tests.

### Naming: Plain English Over Rigid Conventions

The `[MethodUnderTest]_[Scenario]_[ExpectedResult]` convention is unhelpful — it couples the test name to implementation details (method names) and forces complex behavior into a rigid format.

Khorikov's three naming guidelines:

1. **Don't follow a rigid naming policy** — allow freedom of expression
2. **Name the test as if describing the scenario to a non-programmer** familiar with the problem domain
3. **Separate words with underscores** for readability

```csharp
// BAD — rigid convention, coupled to method name
public void IsDeliveryValid_InvalidDate_ReturnsFalse()

// Improvement progression:
public void Delivery_with_invalid_date_should_be_considered_invalid()
public void Delivery_with_past_date_should_be_invalid()  // more specific
public void Delivery_with_a_past_date_is_invalid()       // remove "should be"
```

Don't include the SUT's method name in the test name — you test *behavior*, not methods. If the method is renamed, the test shouldn't need renaming.

### Fixture Reuse: Factory Methods Over Constructors

Extracting shared fixture setup into the test class constructor introduces **high coupling between tests** (changing one test's arrangement affects all) and **diminishes readability** (you can't see the full context in the test method).

**Better approach:** private factory methods with default parameters:

```csharp
private Store CreateStoreWithInventory(Product product, int quantity)
{
    Store store = new Store();
    store.AddInventory(product, quantity);
    return store;
}
```

Tests specify only what's relevant to their scenario. Factory methods don't couple tests to each other. Exception: base class constructors are fine for infrastructure shared by all tests (database connections).

Khorikov prefers **Object Mother** (factory methods with defaults) over **Test Data Builder** (fluent `.With*()` chains) — less boilerplate in C# thanks to optional parameters.

### Parameterized Tests

Group similar facts about a behavior into a single parameterized test. Use `[Theory]` + `[InlineData]` in xUnit:

```csharp
[InlineData("mycorp.com", "email@mycorp.com", true)]
[InlineData("mycorp.com", "email@gmail.com", false)]
[Theory]
public void Differentiates_a_corporate_email_from_non_corporate(
    string domain, string email, bool expectedResult)
{
    var sut = new Company(domain, 0);
    bool isEmailCorporate = sut.IsEmailCorporate(email);
    Assert.Equal(expectedResult, isEmailCorporate);
}
```

**Positive/negative split pattern**: when behavior differs significantly between positive and negative cases, extract the positive test into its own `[Fact]` method with a descriptive name, and keep only the negative cases parameterized:

```csharp
[InlineData(-1)]
[InlineData(0)]
[InlineData(1)]
[Theory]
public void Detects_an_invalid_delivery_date(int daysFromNow) { /* ... */ }

[Fact]
public void The_soonest_delivery_date_is_two_days_from_now() { /* ... */ }
```

This removes the `expected` Boolean parameter entirely from the negative cases (they're all `false`), and the positive case gets its own expressive name.

**`[MemberData]` for complex data**: `[InlineData]` only accepts compile-time constants (literals, `typeof()`). For runtime values like `DateTime.Now.AddDays(-1)`, use `[MemberData]` pointing to a static method:

```csharp
[Theory]
[MemberData(nameof(Data))]
public void Can_detect_an_invalid_delivery_date(
    DateTime deliveryDate, bool expected) { /* ... */ }

public static List<object[]> Data()
{
    return new List<object[]>
    {
        new object[] { DateTime.Now.AddDays(-1), false },
        new object[] { DateTime.Now, false },
        new object[] { DateTime.Now.AddDays(1), false },
        new object[] { DateTime.Now.AddDays(2), true }
    };
}
```

**Decision rule for parameterization**: keep positive and negative cases in a single method only when it's self-evident from the input parameters which case stands for what. Otherwise, extract the positive case. If the behavior is too complicated, don't parameterize at all — represent each negative and positive case with its own test method.

### Fluent Assertions (Ch 3.6)

Assertion libraries restructure assertions to read like plain English, following the [Subject] [action] [object] story pattern:

```csharp
// Standard xUnit — reads backward (expected, actual)
Assert.Equal(30, result);

// Fluent assertion — reads like a sentence
result.Should().Be(30);
```

`result.Should().Be(30)` reads as: "result should be 30" — subject, action, object. Khorikov prefers Fluent Assertions for this readability benefit. The library provides helper methods for numbers, strings, collections, dates, and more.

**Trade-off**: fluent assertions are a dev-only dependency (not shipped to production). The readability improvement is significant enough to justify the additional package in most projects.

Fluent assertions become especially valuable for **state-based tests** where multiple properties need checking (see Ch 6's state verification examples with `BeEquivalentTo` and collection assertions).
