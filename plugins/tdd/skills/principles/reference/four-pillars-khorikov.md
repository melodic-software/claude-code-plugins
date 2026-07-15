# The Four Pillars of a Good Unit Test (Khorikov)

Khorikov's central framework — a universal lens for evaluating any automated test (Ch 4). Every concept in the book derives from these four attributes.

## The Four Pillars

1. **Protection against regressions** — how good the test is at detecting bugs
2. **Resistance to refactoring** — can the test survive refactoring without false positives?
3. **Fast feedback** — how quickly the test executes
4. **Maintainability** — how easy the test is to understand and run

## Pillar 1: Protection Against Regressions

Evaluated by three factors:

- The **amount of code** executed during the test
- The **complexity** of that code
- The code's **domain significance**

"To maximize the metric of protection against regressions, the test needs to aim at exercising as much code as possible." Include external libraries and frameworks in scope — bugs in assumptions about third-party behavior are the most dangerous.

Trivial code (single-line properties, simple constructors) is not worth testing — there's no room for a mistake.

## Pillar 2: Resistance to Refactoring

The degree to which a test can sustain application code refactoring without producing a **false positive** (false alarm).

A **false positive** is when the test fails but the functionality works as intended. This happens when tests couple to the SUT's **implementation details** rather than its **observable behavior**.

Why false positives are devastating:

- They dilute your ability to react to real problems — "cry wolf" effect
- They erode trust in the test suite — developers stop viewing it as a safety net
- They hinder refactoring — fear of false alarms discourages code improvement

"The only way to reduce the chance of getting a false positive is to decouple the test from those implementation details. You need to make sure the test verifies the end result the SUT delivers: its observable behavior, not the steps it takes to do that."

**Resistance to refactoring is non-negotiable.** Unlike the other pillars, it's mostly binary — the test either has it or doesn't. You cannot partially concede it.

## Pillar 3: Fast Feedback

How quickly the test executes. Fast tests can run frequently — shortening the feedback loop to near-zero reduces the cost of fixing bugs.

Slow tests delay feedback, discourage frequent runs, and increase the period during which bugs go unnoticed.

## Pillar 4: Maintainability

Two components:

- **How hard it is to understand the test** — a function of the test's size. Fewer lines = more readable. Treat test code as first-class (don't cut corners to reduce line count)
- **How hard it is to run the test** — a function of out-of-process dependencies. More dependencies = more operational overhead (database servers, network connectivity, etc.)

## The Multiplication Principle

The four pillars combine **multiplicatively**, not additively:

```
Value = [0..1] * [0..1] * [0..1] * [0..1]
```

If any pillar scores zero, the test's total value is zero — regardless of how well it scores on the others. "A test that scores zero in one of the four categories is worthless."

## The Impossibility of the Ideal Test

The first three pillars (protection, resistance, feedback) are **mutually exclusive** — you can maximize two at the expense of the third. An ideal test scoring maximum on all three is impossible.

### Three extreme cases (each sacrifices one pillar)

| Type | High on | Sacrifices | Example |
|------|---------|-----------|---------|
| **End-to-end tests** | Protection + Resistance | Fast feedback | Full system test through UI |
| **Trivial tests** | Resistance + Feedback | Protection | Testing a getter/setter |
| **Brittle tests** | Protection + Feedback | Resistance | Verifying SQL string literal |

### The Strategic Trade-off

Since resistance to refactoring is non-negotiable (binary), the real trade-off is a **slider between protection against regressions and fast feedback**:

- **Unit tests** — favor fast feedback, sacrifice some protection
- **Integration tests** — balanced
- **End-to-end tests** — favor protection, sacrifice feedback speed

Always maximize resistance to refactoring and maintainability. Then choose your position on the protection/feedback slider.

## Test Accuracy

Test accuracy = Signal (bugs found) / Noise (false alarms raised)

- **Protection against regressions** guards against **false negatives** (Type II errors — missed bugs)
- **Resistance to refactoring** guards against **false positives** (Type I errors — false alarms)

"In the short term, false positives are not as bad as false negatives. But as the project grows, false positives start to have an increasingly large effect on the test suite: as important as false negatives."

## The Test Pyramid (through the Four Pillars lens)

The Test Pyramid represents the optimal trade-off:

- **Unit tests** (majority) — fast, cheap, cover edge cases in domain model
- **Integration tests** (middle) — 1-2 per business scenario happy path
- **End-to-end tests** (minority) — only for most critical features

Exception: simple CRUD apps with little domain logic → pyramid becomes a rectangle (equal unit and integration tests).

"Check as many of the business scenario's edge cases as possible with unit tests. Use integration tests to cover one happy path, as well as any edge cases that can't be covered by unit tests."

## Black-Box vs White-Box Testing

| | Protection against regressions | Resistance to refactoring |
|---|---|---|
| **White-box** | Good | Bad |
| **Black-box** | Bad | Good |

Since resistance to refactoring is non-negotiable: **"Choose black-box testing over white-box testing by default."**

"If you can't trace a test back to a business requirement, it's an indication of the test's brittleness. Either restructure or delete this test."

Use black-box when **writing** tests. Use white-box when **analyzing** them (coverage tools to find untested branches, then write black-box tests for those branches).
