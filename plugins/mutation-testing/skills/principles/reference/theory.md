# Why injecting fake bugs tells you anything

The theory is short, forty-odd years old, and worth knowing because it tells you exactly when
mutation testing's answer is trustworthy and when it is not.

Sources: DeMillo, Lipton & Sayward, *Hints on Test Data Selection: Help for the Practicing
Programmer* (IEEE Computer, 1978); Jia & Harman, *An Analysis and Survey of the Development of
Mutation Testing*, IEEE TSE 37(5), 2011 (<https://dl.acm.org/doi/10.1109/TSE.2010.62>). Fetched
2026-08-10.

## Two assumptions

Mutation testing rests on two hypotheses. Both are empirical claims, not theorems.

### The competent programmer hypothesis

Programs written by competent programmers are *nearly* correct. Real defects are small deviations
from a correct program, not wholesale rewrites.

**Consequence:** a single-token synthetic fault resembles a real one closely enough to stand in for
it. This is why operators are small and syntactically local, and why a mutant that changes a program
beyond recognition would prove nothing.

**When it fails:** in code that is not nearly correct — a first draft, a spike, a component with a
misunderstood specification. There, the real bug is not one token away, and a high mutation score
buys less confidence than it appears to.

### The coupling effect

A test suite that detects simple faults will also detect the complex faults built out of them.

**Consequence:** you do not need to enumerate realistic multi-line bugs. Killing the cheap
single-operator mutants is evidence about the expensive compound ones. This is the load-bearing
assumption — without it, mutation score would say nothing about real defect-detection ability.

**When it fails:** for faults that are not compositions of local errors — a wrong algorithm, a
missing requirement, a concurrency interleaving, a security property nobody expressed as behavior.
Mutation testing is silent on all of these. A perfect mutation score is not a correctness argument.

## The equivalent mutant problem

Some mutations produce a program that is *semantically* identical to the original. No test can ever
kill them, because there is no behavioral difference to detect.

```python
# original                          # mutant: <= becomes <
for i in range(0, n):               for i in range(0, n):
    if i <= n:  ...                     if i < n:  ...
```

Both guards are always true inside the loop. The mutant survives forever, and it is not a gap.

Deciding whether two programs are semantically equivalent is **undecidable in general**. This is not
a tooling deficiency that a better tool will fix; it is a property of the problem. Jia & Harman's
survey identifies it as the dominant cost driver in the field, and it is why:

- every mutation score has a permanent, unknowable ceiling below 100%;
- classification of survivors is a *judgment* step, not a computation;
- an "unkillable" verdict should cite evidence, because the alternative — asserting equivalence from
  inspection alone — is exactly where this technique produces false confidence.

**Practical stance:** treat "equivalent" as a claim requiring a demonstration, not a default
explanation for an inconvenient survivor. The failure mode is reaching for equivalence whenever a
test is hard to write.

## What a mutation score is evidence for

Stated precisely, so it is not oversold:

> A high covered-code mutation score is evidence that, **for the behaviors the tests exercise**, the
> assertions are sensitive to small local changes in the implementation.

That is genuinely valuable and narrower than "the code works." It says nothing about behaviors no
test exercises, nothing about whether the specification is right, and nothing about fault classes
outside the operator catalog.

Read alongside Khorikov's framing of test value: a test's protection against regressions is its
guard against false negatives — missed bugs. Mutation testing is the closest available *empirical
measurement* of that specific property, which is why it earns a place beside coverage rather than
replacing the judgment-based assessment of a test suite. It measures one pillar well; it does not
measure resistance to refactoring, fast feedback, or maintainability at all — and a suite optimized
for mutation score alone will degrade those.
