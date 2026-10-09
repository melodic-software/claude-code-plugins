# Characterization Testing

How to get legacy code, or code about to be rewritten, under test before changing it: Feathers'
characterization tests, golden master and approval tests, the sabotage check, and why every one of
them proves sameness rather than correctness.

**Provenance, read first.** This file is **not** a book distillation. Michael Feathers' *Working
Effectively with Legacy Code* (2004) was **not** read; his definition and recipe below come from
his 2016 web page only. The other sources are tool documentation and one 2025 blog post, read on
2026-10-06. The sources, their read depth, and the recheck trigger are in [Sources](#sources) at
the end.

## What a Characterization Test Is

Feathers defines a characterization test as one that documents what a system **actually** does,
not what you wish it did (HIGH, single source: his own definition of the term he coined). His
recipe from the 2016 page:

1. Write a test with a placeholder name that calls the code.
2. Assert a dummy expected value you know is wrong.
3. Run it; the failure reports the actual value. Put that value in the assertion.

The point is the oracle. A characterization test's expected value comes from running the existing
code, which is exactly what makes it useful before a change: the existing behavior is the thing
the change must preserve.

**Editorial synthesis, outside Feathers' page.** This connects to Beck's observational equivalence
([refactoring-under-test.md](refactoring-under-test.md#refactoring-in-tdd-context)): a refactoring
is safe when it does not change the set of passing tests, which puts the burden on having enough
tests. Legacy code has none, so characterization tests supply that burden before the first
refactoring step. It also sits in tension with an expected value taken from an independent source:
for new code, a value read off the implementation restates it; for code being preserved, the old
behavior is the specification. How the `testing` plugin draws that line is `/testing:test-value`'s
call.

## Golden Master, Approval and Snapshot Tests

The same idea at a coarser grain: record the old output once, commit it, and compare every later
run against it. ApprovalTests calls the pair received and approved, Verify calls it received and
verified, Jest calls it a snapshot. It fits batch outputs and large objects where per-field
assertions would be tedious.

In each tool, accepting a changed output is a reviewed step, not a reflex (HIGH: ApprovalTests,
Verify and Jest each document it). Jest names the failure plainly: fix the bug before regenerating,
or the snapshot records the buggy behavior. Volatile values (timestamps, generated ids) are
normalized before the comparison rather than dropped from it: Verify scrubbers, Jest property
matchers, a custom compare hook (MEDIUM after verification; the scope of the claim was narrowed).

An intentional difference is handled as a named, reviewed exception, and the comparison stays
strict everywhere else (HIGH).

## The Sabotage Check

Mark Seemann (2025) adds one step to the recipe: after the assertion holds the observed value,
temporarily break the code under test and watch the new test fail, then restore it (HIGH, single
source: his own post; the post does not discuss AI or LLM rewrites). A characterization test whose
expected value came from the code has never been seen to fail; this is the cheapest way to show it
can.

## Pins Prove Sameness, Not Correctness

Every recorded-baseline test (characterization, golden master, approval, snapshot) asserts that
today's output equals yesterday's. It says nothing about whether yesterday's output was right, so a
baseline accepted without review records whatever bug produced it (HIGH: Feathers' page plus three
tool docs).

Two consequences, stated as this file's reading of the sources:

- Call these tests pins in names and comments, so nobody later reads a green pin as a correctness
  claim.
- A changed baseline that the current change caused is the one most worth reading before
  accepting. An agent never re-approves a snapshot its own edit broke without reading the diff
  first.

## Where the Practice Lives

- Writing characterization, approval or snapshot tests in the project: `/testing:write`.
- Whether a recorded expected value is acceptable for this test: `/testing:test-value`.

## Sources

Read on 2026-10-06, at the depth noted. Recheck trigger: Feathers' or Seemann's page moves or is
revised, or ApprovalTests, Verify or Jest changes its acceptance workflow.

- Michael Feathers, "Characterization Testing" (2016-08-08,
  <https://michaelfeathers.silvrback.com/characterization-testing>). Page read. His book
  *Working Effectively with Legacy Code* (2004) was not read.
- Mark Seemann, "Empirical characterization testing" (2025-11-03,
  <https://blog.ploeh.dk/2025/11/03/empirical-characterization-testing/>). Post read.
- ApprovalTests (<https://approvaltests.com/>), Verify (<https://github.com/VerifyTests/Verify>,
  scrubbers: <https://github.com/VerifyTests/Verify/blob/main/docs/scrubbers.md>), Jest snapshot
  testing (<https://jestjs.io/docs/snapshot-testing>, 30.5 docs). Docs read.
- Scientist compare hook (<https://github.com/github/scientist>) and known-difference ignores
  (<https://github.blog/developer-skills/application-development/scientist/>). Docs read.
