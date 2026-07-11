# The xUnit Example (Beck, Part II)

Beck's second worked example: building a testing framework test-first, in Python. More complex than the Money example — involves reflection, exceptions, and self-referential bootstrapping ("like performing brain surgery on yourself").

## The Problem

Build a testing framework (xUnit) that can: invoke test methods, call setUp/tearDown, handle failures, run test suites, and report results. The bootstrap challenge: writing tests for the very framework you'll use to run them.

## Key Architecture: xUnit

The framework Beck builds has four classes:

| Class | Role |
|-------|------|
| **TestCase** | Base class for test cases. Stores test method name, implements `run()` via Pluggable Selector (reflection). Calls `setUp()` → test method → `tearDown()` |
| **TestResult** | Collecting Parameter. Counts runs and failures, produces summary string |
| **TestSuite** | Composite of TestCases. Iterates through tests, passing a shared TestResult |
| **WasRun** | A concrete TestCase used to test the framework itself. Keeps a log of method calls |

## Key Concepts Introduced

### The 3A Pattern (Ch 19)

Bill Wake's pattern for test structure:

- **Arrange** — Create objects (often shared via setUp)
- **Act** — Stimulate them
- **Assert** — Check results

"The first step, arrange, is often the same from test to test, whereas the second and third steps, act and assert, are unique."

### Test Isolation vs. Performance (Ch 19)

Two constraints in tension:

- **Performance**: reuse objects across tests
- **Isolation**: each test gets fresh objects

"Test coupling — don't go there." Beck opts for isolation: create objects fresh every time via `setUp()`. Test coupling can cause order-dependent failures, or worse, hide real bugs because a previous test set up the right state.

### The Log Pattern (Ch 20)

Instead of multiple boolean flags to verify method call order, keep a string log: `"setUp testMethod tearDown "`. Each method appends to it. This captures both *which* methods were called and *in what order*. Simpler to assert against and easier to debug.

### Template Method (Ch 20)

The `run()` method becomes a Template Method: `setUp()` → test method → `tearDown()`. The concrete test case overrides setUp/tearDown as needed. TestCase provides no-op defaults.

### Collecting Parameter (Ch 23)

TestResult is passed as a parameter to `run()` rather than being returned. This enables TestSuite.run() to accumulate results across multiple tests. "We will allocate the TestResults in the callers. This pattern is called Collecting Parameter."

### Composite Pattern (Ch 23)

TestSuite and TestCase share the same `run(result)` interface. "We want to be able to treat single tests and groups of tests exactly the same." TestSuite iterates through its tests, calling `run(result)` on each.

### Exception Handling (Ch 22)

Test failures are caught via try/except around the test method. When an exception occurs, `result.testFailed()` is called. This separates assertion failures from test execution errors.

## Process Observations

### Bootstrap Problem

"We have a bootstrap problem: we are writing test cases to test a framework that we will be using to write the test cases." Solution: start with manual verification (print statements), then replace with automated assertions as soon as the framework supports them.

### Step Size When Uncertain (Ch 18)

"I look at the size of the steps in the development I've just shown you, and it looks ridiculous. On the other hand, I tried it with bigger steps, spending probably six hours... and starting from scratch twice, and both times I thought I had the code working when I didn't."

### Refactoring Constants to Variables

"Take code that works in one instance and generalize it to work in many by replacing constants with variables. Here the constant was hardwired code, not a data value, but the principle is the same. TDD makes this work well by giving you running concrete examples from which to generalize, instead of having to generalize purely with reasoning."

### Test Order Matters (Ch 21)

"The order of implementing the tests is important. When I pick the next test to implement, I find a test that will teach me something and which I have confidence I can make work." Beck shelved the exception-catching test because it required capabilities he didn't have yet.

### Premature Refactoring (Ch 20)

"Doing a refactoring based on a couple of early uses, then having to undo it soon after is fairly common. Some folks wait until they have three or four uses before refactoring. I prefer to spend my thinking cycles on design, so I just reflexively do the refactorings without worrying about whether I will have to undo them."

## xUnit Retrospective (Ch 24)

### Why Implement Your Own xUnit

Even if your language has one already:

- **Mastery** — "The spirit of xUnit is simplicity. Rolling your own will give you a tool over which you have a feeling of mastery."
- **Exploration** — "When I'm faced with a new programming language, I implement xUnit. By the time I have the first eight to ten tests running, I have explored many of the facilities I will be using in daily programming."

### Failures vs. Errors

"Assertion failures consistently take much longer to debug. Because of this, most implementations of xUnit distinguish between failures — meaning assertion failures — and errors."

## Final To-Do Items Left as Exercises

- Invoke tearDown even if test method fails
- Catch and report setUp errors
- Create TestSuite from a TestCase class automatically
