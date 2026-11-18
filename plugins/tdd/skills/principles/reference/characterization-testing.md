# Characterization Testing

How to get legacy code, or code about to be rewritten, under test before changing it: Feathers'
characterization tests, golden master and approval tests, the sabotage check, and why every one of
them proves sameness rather than correctness.

**Provenance, read first.** This file is **not** a book distillation. Of Michael Feathers'
*Working Effectively with Legacy Code* (2004), only the publisher's free sample was read: chapter
4 and the preface. His definition and recipe below come from his 2016 web page. The other sources
are tool documentation, one 2025 blog post and Martin Fowler's Strangler Fig page. The sources and
their read depth are in [Sources](#sources) at the end.

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

## When the Code Cannot Be Put in a Test Harness

Characterize first is the default. Feathers names the case where it cannot be done yet: "The
hardest part is breaking dependencies around a piece of code well enough to be able to exercise
it in a test harness" (2016 page). His book's dependency-breaking refactorings are the one
exception to tests-before-change: they "are meant to be done without tests, in the service of
putting tests in place" (preface) (HIGH, single author, two of his texts).

The order, as this file's reading of those two texts:

1. Make only the dependency-breaking change: the smallest edit that lets a test reach the code.
   No cleanup, no renamed parameters, no removed duplication in the same step.
2. Write characterization tests through the opening that change made.
3. Refactor, with those tests as the guard.

A dependency is broken at a **seam**: "a place where you can alter behavior in your program
without editing in that place" (ch. 4). Every seam has an enabling point, "a place where you can
make the decision to use one behavior or another". Feathers lists three types, by where the
enabling point sits:

| Seam type | Behavior is swapped by | Enabling point |
|---|---|---|
| Preprocessing | a macro or text substitution before compilation | a preprocessor definition |
| Link | linking or loading a different implementation | outside the program text: the build script or the load path |
| Object | passing or overriding a different object | where the object is chosen, such as an argument list |

He calls object seams "pretty much the most useful seams available in object-oriented programming
languages". Which types a codebase has depends on its language and build; find them there rather
than assuming one.

## Replacing a Legacy System in Steps

When the change is a migration and not a refactoring, Fowler's **Strangler Fig** is the
incremental alternative to a rewrite: "it begins with small additions, often new features, that
are built on top of, yet separate to the legacy code base. As we do this we move bits of behavior
from the legacy system into the new code base." Splitting the old system "will involve identifying
seams that we can insert into the system". Each piece moved is pinned by characterization tests on
the old behavior before it moves (this file's reading; Fowler's page does not prescribe the test).
Planning such a migration belongs to `/planning:design`, where that skill is available.

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

Each source was read at the depth noted.

- Michael Feathers, "Characterization Testing" (2016-08-08,
  <https://michaelfeathers.silvrback.com/characterization-testing>). Page read.
- Michael Feathers, *Working Effectively with Legacy Code* (2004). Read: the publisher's sample
  chapter 4, "The Seam Model"
  (<https://www.informit.com/content/images/0131177052/samplechapter/0131177052_ch04.pdf>), and
  the preface in the publisher's sample pages
  (<https://ptgmedia.pearsoncmg.com/images/9780131177055/samplepages/0131177052.pdf>). The rest
  of the book, the dependency-breaking catalog included, was not read.
- Martin Fowler, "Strangler Fig" (page dated 2024-08-22,
  <https://martinfowler.com/bliki/StranglerFigApplication.html>). Page read.
- Mark Seemann, "Empirical characterization testing" (2025-11-03,
  <https://blog.ploeh.dk/2025/11/03/empirical-characterization-testing/>). Post read.
- ApprovalTests (<https://approvaltests.com/>), Verify snapshot management
  (<https://github.com/VerifyTests/Verify#snapshot-management>, scrubbers:
  <https://github.com/VerifyTests/Verify/blob/main/docs/scrubbers.md>), Jest snapshot testing
  (<https://jestjs.io/docs/snapshot-testing#updating-snapshots>, property matchers:
  <https://jestjs.io/docs/snapshot-testing#property-matchers>, 30.5 docs). Docs read.
- Scientist compare hook (<https://github.com/github/scientist>) and known-difference ignores
  (<https://github.blog/developer-skills/application-development/scientist/>). Docs read.
