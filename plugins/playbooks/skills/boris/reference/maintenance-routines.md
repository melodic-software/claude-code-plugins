# Claude Maintains the Apps: Sections 116–120

Boris's *"Claude maintains the apps"* thread (Part 23, August 13, 2026): a few weeks of daily maintenance routines running unattended against Anthropic's own apps on iOS, Android, Desktop, web, the CLI, and the Agent SDK. Each routine reports into one Slack channel, in a top-level thread of its own, so a dozen parallel jobs stay readable. It is the answer to "what should a routine actually do", building on Section 61 (Routines) and Section 108 (move fixes from prompts into code).

## 116. What to Actually Automate

Boris runs eleven routines: a crash fuzzer, an internal-only feature shipper (ships or deletes forgotten internal features based on usage), a logic simplifier, a logic bugfixer (models tricky logic to find bugs), a duplicate unifier, dead-code removal, a pruner for tests that can't fail, a shipped-feature inliner (removes flags for fully shipped features), a flaky-test fixer, an abstraction improver (flattens over-engineering), and an abstraction police (fixes layering violations).

The selection criterion is what they share. Every one is mechanical, verifiable, and endless, the maintenance you keep meaning to get to. None of them is feature work.

## 117. Probe, Then Delete

Static analysis proves only the easy half of dead code: what nothing references. Code that is reachable but never runs piles up, and no analyzer can say it is safe to cut. The dead-code routine splits the job across two days. It deletes what is provably unreachable, and for code merely suspected it adds logging, waits a day, and removes what never fired. Use the same shape whenever a routine needs a fact it cannot derive from a static read: instrument, then read the results on the next run. A daily routine can afford to be patient.

The request that produced it was eight words, *"also do one for dead code removal"*; the two-phase design was Claude's own, which is Section 110 (judgment, not rules) in production.

## 118. Make the Routine Prove It

Autonomous PRs are useful only if each one is cheap to review, so the evidence requirement goes into the routine prompt: every PR runs `/verify` and posts a repro and a truth table; the logic is formally modeled to spot gaps, duplication, and untested edge cases; and fuzzing runs the real apps with no mocks, because a fuzzer against a mock finds mock bugs. Enumerating the cases is also how the routine finds the gaps it is meant to fix, so the verification artifact and the discovery method are one piece of work. Extends Section 101 (encode verification as a skill).

## 119. Tune the Routine, Not the PR

When a PR comes back wrong, fix the routine, not the PR: fixing the PR buys one PR, fixing the routine buys every future one. Boris asks Claude to tune its own routines, and expects a few days of tuning before a routine is good, so judge a routine on its trend across a week rather than its first run. Direct application of Section 108.

## 120. Expect Half to Land

Over a few weeks across six surfaces: 388 PRs opened, 180 merged, about 46%. Nothing lands unreviewed. Every PR passes Claude Code Review and then human review; the automation generates the work but never approves it. With generation nearly free, the bottleneck moves to review throughput, which is where Boris says the team is looking next. Start with one routine on one repository.
