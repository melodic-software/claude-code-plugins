# Test Design & Organization

## Contents

- [The 3A Pattern (Ch 19, Bill Wake)](#the-3a-pattern-ch-19-bill-wake)
- [Writing the Test](#writing-the-test)
- [xUnit Patterns (Ch 29)](#xunit-patterns-ch-29)
- [What to Test (Ch 32)](#what-to-test-ch-32)
- [Test Quality Signals (Ch 32)](#test-quality-signals-ch-32)
- [The Fibonacci Example (Appendix II)](#the-fibonacci-example-appendix-ii)
- [Khorikov's AAA Refinements (Ch 3)](#khorikovs-aaa-refinements-ch-3)

How to write good tests, what to test, xUnit framework patterns, and when to stop testing. Beck (Ch 25, 27, 29, 32) plus Khorikov's AAA refinements, naming guidelines, fixture reuse, and parameterized tests (Ch 3).

## The 3A Pattern (Ch 19, Bill Wake)

Every test has three phases:

1. **Arrange**: create objects (fixture)
2. **Act**: stimulate them
3. **Assert**: check results

Arrange is often shared (setUp); Act and Assert are unique per test.

## Writing the Test

### Assert First (Ch 25)

Start from the assertion and work backward. This forces you to answer "what's the right answer?" and "how do I check?" before everything else.

### Test Data (Ch 25)

- Use data that makes tests easy to read: "you are writing tests to an audience"
- If there's a difference in data, it should be meaningful
- Never use the same constant for two purposes: test `3 + 4`, not `2 + 2` (what if args are reversed?)
- Don't use a list of 10 items when 3 leads to the same design decisions

### Evident Data (Ch 25)

Make the relationship between inputs and expected outputs visible in the test itself: write the expected value as the calculation from the inputs (100 / 2 × (1 − 0.015)), not as the precomputed result (49.25).

"I can read this test and see the connection between the numbers used in the input and the numbers used to calculate the expected result."

### Child Test (Ch 27)

When a test is too big (requires multiple changes to work), write a smaller test that represents the broken part. Get the small one working, then reintroduce the big one. "Even ten minutes with a red bar gives me the willies."

### One Step Test (Ch 26)

"Pick a test that will teach you something and that you are confident you can implement." Programs grow from **known to unknown**, neither top-down nor bottom-up.

### Starter Test (Ch 26)

Start with a trivially simple variant. For a polygon reducer: input = empty polygon list, output = empty polygon list. "Bing! The first test is running."

## xUnit Patterns (Ch 29)

### Assertion

Be specific: `assertEquals(50, rectangle.area())` not `assertTrue(rectangle.area() != 0)`. Expected value goes first. Test observable behavior, not implementation: don't check `contract.status.class`. Check what the status *enables* (like `contract.startDate()`).

"Wishing for white box testing is not a testing problem, it is a design problem."

### Fixture

Common setup code extracted to `setUp()`. Each test gets a fresh instance, with no sharing between tests. "If I find myself wanting a slightly different fixture, I start a new subclass of TestCase."

There's no simple 1:1 relationship between test classes and model classes. "Sometimes one fixture serves to test several classes. Sometimes two or three fixtures are needed for a single model class."

### External Fixture

Use `tearDown()` to release external resources (files, connections). xUnit guarantees tearDown runs even if the test fails. Eliminates noisy try/finally in every test.

### Test Method

- Name begins with "test" (convention for auto-discovery)
- Name should tell a future reader WHY the test was written: `testAssertPosInfinityNotEqualsNegInfinity`
- Aim for 3+ lines minimum, straightforward top-to-bottom
- "If a test method is getting long and complicated, play Baby Steps"

### Exception Test

Call the code expected to throw, and fail the test if it returns normally. Only catch the specific exception you expect.

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

1. **Confidence**: never delete a test if it reduces your confidence
2. **Communication**: if two tests exercise the same path but speak to different scenarios, keep both

"If you have two tests that are redundant with respect to confidence AND communication, delete the least useful."

## Test Quality Signals (Ch 32)

Tests that suggest **design problems** (not test problems):

| Signal | Design problem |
|--------|---------------|
| **Long setup code** | Objects are too big, need splitting |
| **Setup duplication** | Too many objects too tightly intertwined |
| **Long running tests** | Bits and pieces are hard to test in isolation |
| **Fragile tests** | One part surprisingly affects another, hidden coupling |

"The equivalent of 9.8 m/s² is the ten-minute test suite. Suites that take longer than ten minutes inevitably get trimmed."

### Coverage (Ch 17)

- Statement coverage: TDD should yield ~100%. JProbe found only `Money.toString()` uncovered (debugging aid, not model code)
- Defect insertion (Jester): only `Pair.hashCode()` survived, the faked `return 0` implementation
- Two ways to improve coverage: write more tests OR simplify the code. "Refactoring reduces paths to cover"

For Khorikov's deeper treatment of coverage metrics: [code-coverage-khorikov.md](code-coverage-khorikov.md)

## The Fibonacci Example (Appendix II)

A compact TDD demo that "turned on the light" for reviewers. Drives the implementation entirely from tests.

"There we have Fibonacci, derived totally from the tests." The key move: `return 2` → `return 1 + 1` → `return fib(n-1) + 1` → `return fib(n-1) + fib(n-2)`. Each step replaces a constant with an expression, driven by the data.

---

## Khorikov's AAA Refinements (Ch 3)

### Section Sizing Rules

- **Arrange**: the largest section. If significantly larger than act + assert combined, extract into private factory methods (Object Mother pattern) or a base class
- **Act**: should be a **single line** for unit tests. Two or more lines suggest the SUT's API lacks encapsulation (invariant violation risk). Exception: utility/infrastructure code where multi-step act is acceptable
- **Assert**: multiple assertions are fine. A unit of behavior can have multiple outcomes. But watch for assertion sections that grow too large (sign of a missing value object with equality semantics)

### Avoid `if` Statements in Tests

A test should be a simple, linear sequence with no branching. An `if` in a test means it verifies too many things. Split it into separate tests.

### Naming: Plain English Over Rigid Conventions

The `[MethodUnderTest]_[Scenario]_[ExpectedResult]` convention is unhelpful. It couples the test name to implementation details (method names) and forces complex behavior into a rigid format.

Khorikov's three naming guidelines:

1. **Don't follow a rigid naming policy**: allow freedom of expression
2. **Name the test as if describing the scenario to a non-programmer** familiar with the problem domain
3. **Separate words with underscores** for readability

Refine a name toward the specific fact it states: "delivery with a past date is invalid", not "delivery with invalid date should be considered invalid". Name the specific case (a past date, not an invalid one), and state a fact, not a wish (drop "should be").

Don't include the SUT's method name in the test name, since you test *behavior*, not methods. If the method is renamed, the test shouldn't need renaming.

### Fixture Reuse: Factory Methods Over Constructors

Extracting shared fixture setup into the test class constructor introduces **high coupling between tests** (changing one test's arrangement affects all) and **diminishes readability** (you can't see the full context in the test method).

**Better approach:** private factory methods with default parameters.

Tests specify only what's relevant to their scenario. Factory methods don't couple tests to each other. Exception: base class constructors are fine for infrastructure shared by all tests (database connections).

Khorikov prefers **Object Mother** (factory methods with defaults) over **Test Data Builder** (fluent `.With*()` chains). Object Mother needs less boilerplate where the language has optional parameters.

### Parameterized Tests

Group similar facts about a behavior into a single parameterized test.

**Positive/negative split pattern**: when behavior differs significantly between positive and negative cases, extract the positive test into its own test method with a descriptive name, and keep only the negative cases parameterized.

This removes the `expected` Boolean parameter entirely from the negative cases (they're all `false`), and the positive case gets its own expressive name.

**Decision rule for parameterization**: keep positive and negative cases in a single method only when it's self-evident from the input parameters which case stands for what. Otherwise, extract the positive case. If the behavior is too complicated, don't parameterize at all. Represent each negative and positive case with its own test method.

### Readable Assertions (Ch 3.6)

Assertion libraries restructure assertions to read like plain English, following the [Subject] [action] [object] story pattern: an assertion that reads as "result should be 30" names the subject, the action and the object in that order.

That readability matters most for **state-based tests** where multiple properties need checking (see Ch 6's state verification examples).
