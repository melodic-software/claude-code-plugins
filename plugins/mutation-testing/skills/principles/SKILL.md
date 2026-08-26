---
description: "Answers mutation-testing questions from the primary literature (DeMillo/Lipton/Sayward, Jia & Harman, Google's ICSE-SEIP papers, and the Stryker/PIT/Infection tool docs), producing WHY reasoning about what a surviving mutant means. Use when: 'what is mutation testing', 'mutation score vs coverage', 'what is test strength', 'killed vs survived mutant', 'equivalent mutant', 'which mutation operators', 'why is my mutation score low', 'is mutation testing worth it', 'should we gate on mutation score', 'what is an arid node', 'coupling effect', 'competent programmer hypothesis', not for HOW to run a mutation tool in your project (use `/mutation-testing:setup` and `/mutation-testing:audit`)."
argument-hint: "[question or concept]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Answer mutation-testing questions from the primary literature
---

# Mutation Testing Knowledge Base

Distilled from the primary sources, the foundational papers, the industrial-scale reports, and the
tool documentation that defines the vocabulary everyone else borrows. Reference files in
`reference/` are source-attributed; this file routes and answers the common questions without a load.

## Routing Table

| Query about... | Load |
|---|---|
| Mutant states (killed/survived/no-coverage/timeout), operator catalogs, what a mutation actually is | [operators-and-states.md](reference/operators-and-states.md) |
| Mutation score, covered-code score, test strength, MSI, the oracle gap, what to report | [metrics.md](reference/metrics.md) |
| Cost, diff-scoping, arid nodes, productive vs unproductive mutants, suppression, why not to gate | [scaling-and-suppression.md](reference/scaling-and-suppression.md) |
| Which tool for which ecosystem, what each supports, what to do when no tool exists | [tooling.md](reference/tooling.md) |
| Equivalent mutants, coupling effect, competent programmer hypothesis, the theory | [theory.md](reference/theory.md) |

## Quick decision guide (no load required)

**"What is mutation testing?"**. Coverage tells you a line *executed*. It cannot tell you the line
was *checked*. Mutation testing introduces a small deliberate fault (a **mutant**), re-runs the
tests, and observes: tests fail → the mutant is **killed**, something genuinely asserted on that
behavior; tests pass → the mutant **survived**, that line ran and nothing noticed it was wrong. The
mutation is always reverted; the source is unchanged at the end.

**"Is it just better coverage?"**. It answers a different question. Coverage measures execution;
mutation testing measures *fault detection*. PIT states it directly: line coverage "does **not** check
that your tests are actually able to **detect faults**." A file at 100% coverage and 40% mutation
score has tests that run the code and assert almost nothing about it.

**"Which number do I look at?"**. The **covered-code** one, always. Plain mutation score mixes two
unrelated problems: "my tests are weak" and "I have no tests here." The covered-code variant
(PIT calls it *test strength*, Infection calls it *Covered Code MSI*) isolates the first. A wide gap
between the two means the coverage you have is thin, not that the tests are bad.

**"Should we fail the build on a mutation score?"**. No, and this is the single most common way
adoption fails. The score is depressed by equivalent mutants that no test can ever kill, so a hard
threshold rewards suppressing mutants over writing tests. Report it; do not gate on it.
Scaling and suppression mechanics: see [scaling-and-suppression.md](reference/scaling-and-suppression.md).

**"Isn't this too slow to be practical?"**. Naive whole-repo mutation testing is, and that is why
the technique sat unused for thirty years. The industrial answer is architectural, not
computational: mutate only the **changed lines**, at most **one mutant per line**, suppress
uninteresting nodes, and surface the result as a review-time prompt rather than a report. Google
reports a median of **7 mutants per changelist** under that regime against **820** for traditional
mutagenesis.

**"A mutant survived. Now what?"**. Three possible answers, and telling them apart is the whole
skill:

1. **Productive**, a real gap. Write a test that kills it.
2. **Equivalent**, the mutated program is semantically identical to the original, so no test can
   kill it. Not a defect, not a suppression; the check itself is wrong for that node.
3. **Arid**. Killable, but killing it would not improve the suite (a log line, a trivial
   accessor). Suppress it *with a written reason*.

**"Why can't the tool tell me which?"**. Deciding equivalence is undecidable in general
(Jia & Harman). That is why the classification is a judgment step, and why
`/mutation-testing:audit` delegates it to a fresh context rather than to the context that authored
the tests.

## What this skill does NOT do

- Run a mutation tool. That is `/mutation-testing:audit`.
- Install or configure one. That is `/mutation-testing:setup`.
- Answer general test-design questions (mocking, four pillars, classical vs London). Those belong to
  `/tdd:principles` when the `tdd` plugin is installed; without it, consult your project's own
  test-design guidance.
