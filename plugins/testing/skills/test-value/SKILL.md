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
implementation. `/tdd:principles` (when the `tdd` plugin is enabled) carries the wider Beck and
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

### A test you wrote from code you just wrote

Its expected value has no independent source unless it comes from the list above. Reading your
own code to pick the value copies its output by another route.

Verification record. Claim: LLM-generated test oracles mainly capture the code's actual behavior
rather than its expected behavior, and can validate bugs (the first paper also finds them better at
detecting faults than EvoSuite's). Basis: https://arxiv.org/abs/2410.21136,
https://arxiv.org/abs/2412.14137, https://arxiv.org/abs/2607.22883 (abstracts read). Measured on
LLM test generators run on benchmark repositories; the transfer to an agent writing tests mid-task
is inferred. As of 2026-10-06. Recheck when a study measures an interactive coding agent's own
tests, or one of the three papers is revised.

### A property is stated before it runs

A property is a source only when it comes from the spec, requirement, docstring or issue and is
written down before it runs against the code. A property found by watching what the code does is a
recording, and one that re-implements the code (`add(a, b) === a + b`) is the restated expectation
this section rules out. A new property needs evidence that it can fail: a mutant it kills
(`/mutation-testing:audit --exercised`, when that plugin is enabled) or a known-bad input marked
expected-fail, such as Hypothesis `@example(...).xfail()`.

Verification record. Claim: a material share of LLM-written property tests are unsound or
superficial (a wrong implementation also satisfies them), and Hypothesis documents expected-failing
examples as a check that a test does fail on some inputs. Basis:
https://aclanthology.org/2026.findings-acl.683/, https://arxiv.org/abs/2307.04346,
https://hypothesis.readthedocs.io/en/latest/reference/api.html. Measured on Python libraries and
benchmark functions. As of 2026-10-06. Recheck when Hypothesis renames or drops `example.xfail`.

### In a rewrite, the old code is the source and the test is a pin

When code is replaced, migrated or ported, or pinned before a refactor, the old implementation or
output recorded from it is the independent source for the new code, so copying that output is
allowed here. Such a test is a pin: it proves sameness, not correctness, and keeps any bug the old
code had. Name it as a pin, and before trusting it break the code under test on purpose and watch
the pin fail. The record is in §4.

### A canned response names its source

A stub, fake or recording standing in for an unmanaged dependency (§2) feeds values the code acts
on, so each canned response names where it came from: a recorded real response replayed read-only
in CI, the provider's published schema or sandbox, or a contract test both sides run. A response
written from the same guess about the API as the code passes on the shared mistake. Recordings are
editable files, so one is independent only while the implementer cannot rewrite it; a re-recorded
or hand-edited one is a new claim to review. Consumer-driven contract tools such as Pact need the
provider to run them too, which rules them out for public third-party APIs.

Verification record. Claim: a contract test checks that calls to a test double return what the
real service would; Pact's docs say it does not fit APIs whose provider will not also use Pact or
whose consumers cannot be identified, such as public APIs; vcrpy records real responses once and
its `none` record mode errors on any unrecorded request. Basis:
https://martinfowler.com/bliki/ContractTest.html,
https://docs.pact.io/getting_started/what_is_pact_good_for,
https://vcrpy.readthedocs.io/en/latest/usage.html. As of 2026-10-06. Recheck when Pact's
suitability page or vcrpy's record modes change.

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

A rewrite pin (§1) is not the copying Beck rules out: its values come from a second
implementation, the old one, so the check is double, but on sameness only.

Verification record. Claim: a characterization test documents a system's actual behavior rather
than its desired behavior; temporarily sabotaging the code under test confirms each
characterization assertion can fail; Jest says to fix a bug before regenerating snapshots so the
snapshot does not record it. Basis: https://michaelfeathers.silvrback.com/characterization-testing,
https://blog.ploeh.dk/2025/11/03/empirical-characterization-testing/,
https://jestjs.io/docs/snapshot-testing. As of 2026-10-06. Recheck when Feathers or Seemann
revises the post, or Jest's snapshot page changes its regeneration advice.

## Next

- The suite needs checking for the shapes in the taxonomy below: /testing:audit.
- A folder of low-value tests needs rewriting or pruning: /testing:cleanup <folder>.

## 5. Taxonomy, keyed to `/testing:audit` rule ids

**Cannot fail** (green whatever the code does):

| Rule | Shape | Fix |
|---|---|---|
| `rule-zero-assertion` | a test body with no assertion | assert the behavior |
| `rule-recomputed-expectation` | both sides the same expression: `expect(LIMIT).toBe(LIMIT)` | take the expected side from §1 |
| `rule-inert-assertion` | an assertion that never runs: unawaited `toBeVisible()`, `assert (x == 1, "msg")`, `m.called_once_with(...)`, bare `.Should();`, `Assert.True(true)`, `Assert.NotNull(typeof(T))` | await it, fix the tuple, use `assert_called_once_with`, assert a value the code computes |
| `rule-conditional-assertion` | every assertion inside an `if`, a `catch` or a loop over the result; a C# `return;` before every assertion | assert unconditionally; check the length first; skip the test instead of returning |
| `rule-flaky-passes-suite`, `rule-only-not-forbidden` | Playwright retries without `failOnFlakyTests`; no `forbidOnly` | set both in the config |

**Checks little** (can fail, but misses most wrong answers):

| Rule | Shape | Fix |
|---|---|---|
| `rule-mock-only-oracle` | every assertion is a mock interaction | assert a result or state, unless §2 applies |
| `rule-recomputed-derived` | expected rebuilt the way the code computes it: `expect(add(a, b)).toBe(a + b)`, `items.reduce(...)`; passes when test and code share a mistake, and proves no specified value | a hand-computed literal (§1) |
| `rule-weak-oracle` | `toBeDefined`, `is not None`, `toThrow()` alone | assert the value or the exception type |
| `rule-throw-only-oracle` | `var w = new Widget(); Assert.NotNull(w);`: only a throwing constructor fails it | assert what the constructor sets; `cant-fail-ok: <why>` for a smoke test kept to prove wiring |
| `rule-snapshot-only` | a snapshot is the only oracle | review it as code; scrub volatile values (times, ids, seeds) with the tool's matcher or scrubber; when your own change breaks it, fix the bug or confirm the diff is intended before regenerating, never re-approve blind (§4) |

**Change detectors** (fail on any edit, prove no behavior):

| Rule | Shape | Fix |
|---|---|---|
| `rule-constant-restatement` | `expect(X_POST_CHARACTER_LIMIT).toBe(280)` | test the boundary (280 accepted, 281 rejected); `cant-fail-ok: <why>` for an external contract literal |
| `rule-source-text-read` | reading a `.tsx` file and asserting `indexOf` order | render or call it |

**Judgment only** (no rule; the reviewer decides): a stub of a platform API that hides its error
modes (`vi.stubGlobal('AudioContext', ...)`); mocking an internal collaborator; testing a private
method; a test that breaks on a behavior-preserving refactor; a name that says how, not what; a
snapshot written by hand the same way the code computes it; all tests written before any code.
Also judgment only:

- a negative test that passes for an unrelated reason: the rejection comes from a different guard,
  or from an input the production path never reaches;
- a fixture that supplies the outcome the code should produce (the receipt, the ordering, the
  callback), or a store asserted on that the path under test never writes;
- a mock that implements the behavior the test asserts, or one mock standing in for different
  APIs;
- a name that promises more than the assertions check, such as "clears the cache" asserting the
  cache still holds the entry: judge the assertions, not the name;
- a hand-copied inventory (an export list, a manifest, declared capability flags) compared to the
  source: a change detector, unless the list is an external contract (`cant-fail-ok: <why>`), and a
  capability flag is tested by exercising what it promises;
- a test kept alive only to preserve an export, global or wrapper that no production caller uses.
