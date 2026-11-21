# Code Coverage and the Goal of Unit Testing (Khorikov)

Coverage metrics, the goal of unit testing, and properties of a successful test suite (Ch 1). Establishes the economic framing that underpins the rest of the book.

## The Goal of Unit Testing

The goal is **not** better design. That's a pleasant side effect.

> "The goal is to enable sustainable growth of the software project."

Projects without tests start fast but hit stagnation as software entropy accumulates. Each change increases disorder; without constant cleaning and refactoring, the system becomes unreliable. Tests act as a safety net, insurance against regressions that lets you introduce features and refactor with confidence.

**But tests alone aren't enough.** Bad tests produce the same stagnation, just delayed. The project still eventually hits the point where progress grinds to a halt.

## Testability as an Indicator

The ability to unit test code is a **good negative indicator**. It points out poor-quality code (tight coupling) with high accuracy.

The ability to unit test code is a **bad positive indicator**. Easy-to-test code doesn't necessarily mean quality code. "The project can be a disaster even when it exhibits a high degree of decoupling."

This asymmetry (good negative / bad positive) recurs throughout the chapter as the central insight about coverage metrics.

## Code Is a Liability

> "Code is a liability, not an asset. The more code you introduce, the more you extend the surface area for potential bugs in your software, and the higher the project's upkeep cost."

Tests are code too. They aim at a particular problem (ensuring correctness), but they're vulnerable to bugs and require maintenance like any other code. Tests whose net value is close to zero or negative, because of high maintenance costs, actively damage the project.

## Coverage Metrics

### Code Coverage (Test Coverage)

```
Code coverage = Lines of code executed / Total number of lines
```

**Problem: easily gamed by code compaction.** Inlining an `if` statement into a single `return` can raise coverage (in a five-line method, from 80% to 100%) with the same test and the same verification. "The more compact your code is, the better the test coverage metric becomes, because it only accounts for the raw line numbers."

### Branch Coverage

```
Branch coverage = Branches traversed / Total number of branches
```

More precise than code coverage, and not affected by code reformatting. An `if` has 2 branches whether it is written as a statement or inlined. But still insufficient.

### Two Fundamental Problems

**1. Coverage can't guarantee outcomes are verified, only that code was executed.**

A method that returns a result and also records it as a side effect can reach 100% code coverage from a test that asserts only the return value. The side effect is never verified. Coverage metrics measure execution, not assertion.

The extreme case is **assertion-free testing**: a test that exercises every path and asserts nothing reaches 100% coverage with 0% value.

**2. Coverage can't account for code paths in external libraries.**

A method that only delegates to a library's integer parser shows 100% branch coverage, but the parser has hidden branches for null, empty string, non-numeric input, and overflow, none of which the test exercises. "Coverage metrics have no way to see how many [external branches] there are and how many of them your tests exercise."

## Don't Target a Coverage Number

> "The best way to view a coverage metric is as an indicator, not a goal in and of itself."

Khorikov's hospital analogy: A patient's high temperature indicates a fever. But the hospital shouldn't make the proper temperature a *goal* to target. Otherwise they'd install an air conditioner on the patient's skin.

> "Targeting a specific coverage number creates a perverse incentive that goes against the goal of unit testing. Instead of focusing on testing the things that matter, people start to seek ways to attain this artificial target."

**The rule:**

- Low coverage (below ~60%) is a **certain sign of trouble**: lots of untested code
- High coverage **doesn't mean anything**. The tests might be assertion-free, coupled to implementation details, or missing external library edge cases
- "It's good to have a high level of coverage in core parts of your system. It's bad to make this high level a requirement. The difference is subtle but critical."

## A Successful Test Suite

There's no automated way to measure test suite quality. You must evaluate each test individually. A successful suite has three properties:

> **Editorial note: one partial exception, outside Khorikov's text.** The claim above is about
> *quality* as this chapter defines it, and it stands. But one property of a test suite is measurable
> automatically by **mutation testing**: whether its assertions can actually *detect a fault*, as
> opposed to merely executing the code. Mutation testing introduces a small deliberate fault, re-runs
> the tests, and sees whether anything goes red. A file at 95% coverage whose tests kill 40% of
> mutants is exercised
> but not checked, and no coverage metric can tell you that. The measurement is genuinely partial:
> it says nothing about the other properties this chapter names, its ceiling is unknowable because
> equivalent mutants cannot all be removed, and targeting the number reproduces exactly the perverse
> incentive described above. For the operators, the metric family, and why not to gate on it, invoke
> `/mutation-testing:principles` when the `mutation-testing` plugin is enabled; without it, the
> one-line version is that the metric to read is the *covered-code* mutation score, because the
> plain score mixes weak tests with absent tests, and that it belongs beside coverage as an
> indicator rather than as a target.

### 1. Integrated into the Development Cycle

"The only point in having automated tests is if you constantly use them." Run on every code change, even the smallest.

### 2. Targets the Most Important Parts

Not all code is worth equal testing attention. Priority:

- **Domain model (business logic)**: highest ROI, most of your unit testing effort
- **Infrastructure code**: may warrant testing if complex algorithms exist
- **External services and dependencies**: covered by integration tests
- **Glue code**: lowest priority

"You have to keep the domain model separated from all other application concerns so you can focus your unit testing efforts on that domain model exclusively."

### 3. Maximum Value with Minimum Maintenance Costs

The hardest property. Two sub-skills:

- **Recognizing** a valuable test (and, by extension, a test of low value)
- **Writing** a valuable test, which is harder, because tests and underlying code are intertwined

"It's impossible to create valuable tests without putting significant effort into the code base they cover." This is why the book devotes significant space to code design, not just testing technique.

## Key Takeaway

Coverage metrics are a **lagging indicator**, not a leading one. They can tell you "you definitely don't have enough tests" but can never tell you "you have enough good tests." The only reliable measure of test suite quality is evaluating each test against a framework, which Khorikov provides in Chapter 4 (the Four Pillars).
