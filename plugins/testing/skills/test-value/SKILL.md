---
description: "What makes a test worth keeping: where each expected value must come from, when call-count and database checks are legitimate, and the can't-fail and change-detector taxonomy keyed to testing:audit rule ids. Use when writing, reviewing or fixing tests, or asking 'is this test worth keeping', 'where should the expected value come from', 'is this test tautological', 'should I assert this mock call'."
user-invocable: false
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Where expected values come from and which tests earn their keep
---

# Test value

A test is worth keeping when it fails for the bug it guards and passes for any correct
implementation. `/tdd:principles` (when the `tdd` plugin is installed) carries the wider Beck and
Khorikov doctrine.

## 1. Every expected value names its independent source

Before writing an assertion, name where its expected value comes from:

- a literal the requirement states (`280 characters accepted, 281 rejected`);
- a worked example from the spec, the issue or the API contract;
- the bug report, for a regression test (the value the reporter expected);
- a value computed by hand, outside the code under test;
- a known fixture whose content the test did not derive from the code.

If the only way to get the value is to run the code under test, or to repeat its algorithm in the
test, there is no independent source, and there is no unit test to write. Test at a level that
has one (a property, a round trip against a specified format, an end-to-end outcome), or leave the
code untested and say so. Never copy the code's actual output into the expected value: it turns the
test into a recording of whatever the code did.

## 2. Call counts are legitimate at unmanaged, state-changing boundaries

Asserting that a call happened, and how often, is correct when the dependency is **unmanaged**
(out-of-process, observable by other systems: a payment API, an email gateway, a message bus) and
the call **changes its state**: there the call is the behavior, and verifying that the charge
request was sent once (`Times.Once`) is the test to write. On an internal collaborator, a managed
dependency or a query call the same assertion pins the implementation and breaks on refactor.

Verification record. Claim: only unmanaged dependencies should be mocked, and interactions with
them (calls that change their state) are observable behavior to verify. Basis:
https://enterprisecraftsmanship.com/posts/when-to-mock/. As of 2026-09-29. Recheck when that post
or Khorikov's *Unit Testing Principles, Practices, and Patterns* publishes a revision that changes
the managed/unmanaged split.

## 3. A managed database is real, and reading it back is state verification

A database only your application touches is a **managed** dependency: test against a real
instance (a container, LocalDB), not a mock or an in-memory fake. After the act step, reading the
resulting row directly (`context.Blogs.SingleAsync(...)`, `SELECT ... WHERE id = ?`) is legitimate
state verification. What makes such a test weak is its oracle, not the read: `expect(row)
.toBeDefined()` passes for wrong data; assert the fields.

The named exception is the EF Core carve-out: mocking `DbContext` is acceptable for non-query
writes (verifying that code called `Add` or `SaveChanges()`). Never mock `DbSet` for queries; LINQ
over an in-memory collection does not behave like the provider.

Verification record. Claim: mocking `DbContext` "can be a good approach for testing various
non-query functionality, such as calls to Add or SaveChanges()", mocking `DbSet` for queries should
be avoided, and tests against the production database system are recommended. Basis:
https://learn.microsoft.com/en-us/ef/core/testing/choosing-a-testing-strategy. As of 2026-09-29
(page updated 2026-06-26). Recheck when that page's "Mocking or stubbing DbContext and DbSet"
section or its Summary changes.

## 4. Refactoring stays inside the loop

Red, green, then refactor, every cycle, one test at a time. Refactoring is not a phase after all
the tests are written, and writing every test on the list before any implementation is a mistake:
bulk tests check imagined behavior. Keep the test list; turn one item into a test at a time.

Verification record. Claim: Canon TDD is five steps (list, one test, make it pass, "Optionally
refactor to improve the implementation design", repeat until the list is empty), and "copying
actual, computed values & pasting them into the expected values of the test ... defeats double
checking". Basis: https://newsletter.kentbeck.com/p/canon-tdd (redirected from
tidyfirst.substack.com; published 2023-12-11). As of 2026-09-29. Recheck when Beck publishes a
revision of Canon TDD or a successor post that changes step 4.

## 5. Taxonomy, keyed to `/testing:audit` rule ids

**Cannot fail** (green whatever the code does):

| Rule | Shape | Fix |
|---|---|---|
| `rule-zero-assertion` | a test body with no assertion | assert the behavior |
| `rule-recomputed-expectation` | both sides the same expression: `expect(LIMIT).toBe(LIMIT)` | take the expected side from §1 |
| `rule-recomputed-derived` | expected rebuilt from the inputs: `expect(add(a, b)).toBe(a + b)`, `items.reduce(...)` | a hand-computed literal |
| `rule-inert-assertion` | an assertion that never runs: unawaited `toBeVisible()`, `assert (x == 1, "msg")`, `m.called_once_with(...)`, bare `.Should();` | await it, fix the tuple, use `assert_called_once_with` |
| `rule-conditional-assertion` | every assertion inside an `if`, a `catch` or a loop over the result | assert unconditionally; check the length first |
| `rule-flaky-passes-suite`, `rule-only-not-forbidden` | Playwright retries without `failOnFlakyTests`; no `forbidOnly` | set both in the config |

**Checks little** (can fail, but misses most wrong answers):

| Rule | Shape | Fix |
|---|---|---|
| `rule-mock-only-oracle` | every assertion is a mock interaction | assert a result or state, unless §2 applies |
| `rule-weak-oracle` | `toBeDefined`, `is not None`, `toThrow()` alone | assert the value or the exception type |
| `rule-snapshot-only` | a snapshot is the only oracle | review it as code; it is fine once reviewed |

**Change detectors** (fail on any edit, prove no behavior):

| Rule | Shape | Fix |
|---|---|---|
| `rule-constant-restatement` | `expect(X_POST_CHARACTER_LIMIT).toBe(280)` | test the boundary (280 accepted, 281 rejected); `cant-fail-ok: <why>` for an external contract literal |
| `rule-source-text-read` | reading a `.tsx` file and asserting `indexOf` order | render or call it |

**Judgment only** (no rule; the reviewer decides): a stub of a platform API that hides its error
modes (`vi.stubGlobal('AudioContext', ...)`); mocking an internal collaborator; testing a private
method; a test that breaks on a behavior-preserving refactor; a name that says how, not what; a
snapshot written by hand the same way the code computes it; all tests written before any code.

Matt Pocock's `tdd` skill and his 2026 talk supply most of these examples. This skill corrects
him in five places: T1 and T2 are change detectors, not tests that cannot fail; call counts are
right at unmanaged boundaries; a direct database read is state verification; a reviewed snapshot
is a real oracle; and refactoring stays in the loop.

## Next

/testing:audit

Runs the deterministic detector for every rule in the taxonomy above over the suite.
