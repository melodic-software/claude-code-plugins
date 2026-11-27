# Rule native-surface overlaps by five ordered tests

- Status: accepted
- Date: 2026-11-27
- Related: [audit-native-overlap](../../plugins/harness-ops/skills/audit-native-overlap/SKILL.md) (the store, its verdicts and who may write one);
  [native surfaces](../native-surfaces.md) (the generated view);
  [Claude Ship](https://code.claude.com/docs/en/claude-ship) and
  [/ship and /steward](https://code.claude.com/docs/en/ship-command) (the surfaces that prompted this record)

## Context

Claude Code now ships surfaces that overlap our PR tooling: `/ship` (`ship-local`) and `/steward`
open, review and watch a pull request, and the Claude Ship agents (Code Review, PR Steward, Claude
Approvals) do the same work per organization. The native-surfaces store records one verdict per
pair of a native surface and one of our components (`prefer-native`, `prefer-ours`,
`complementary`, `superseded`, `defer`), but nothing said how a verdict is reached. A session may
write a verdict only "acting on the owner's recorded direction" (audit-native-overlap SKILL.md
"Three things it is not"). This record is that direction.

## Decision

1. **Five tests, in order.** Each verdict is decided by: (1) the surface keeps the consumer's pull
   request contract; (2) it keeps merge authority where the consumer's rules put it; (3) it bills
   nothing the consumer has not opted in to; (4) it is available on the consumer's plan; (5) on a
   tie, prefer the built-in.
2. **Shipped verdicts read the consumer.** For a verdict that changes a shipped plugin, all four
   tests read the consumer's own settings: tests 1 and 2 its source-control conventions, test 3 its
   cost choice, test 4 its plan. This repository's own rules decide only verdicts about this
   repository's lanes, where a billed surface goes to the owner.
3. **Mapping.**
   - A test 1 or 2 failure is `prefer-ours` when both do the same job, with a reason naming the
     failed test, and `complementary` when the jobs differ.
   - A surface missing on some consumers' plans, or gated, is ruled on its job like any other,
     carries the `gated` marker, and caps at `prefer-native`: ours stays the fallback wherever it is
     absent, so it is never `superseded`.
   - Passing tests 1 to 4 on the same job is `prefer-native`; it is `superseded` only when ours
     has no behavior the built-in lacks.
   - A different job is `complementary`. A surface the evidence cannot judge yet is `defer`.
4. **One committed verdict per pair.** The verdict judges the job. Per-consumer conditions (a gate,
   billing, the consumer's contract) apply at run time through the store's presence-gated baked
   phrase and its `integration` field; no row is written per consumer.
5. **Billing.** A billed surface is ruled on its job, and routing to it needs the consumer's opt-in.
   The store marker and the consumer key that carry this are added with the first billed row that
   needs routing.
6. **Plan-limited agents.** Surfaces available only on some plans (the Claude Ship agents today)
   get a docs-only record under `docs/upstream/` until a consumer's plan includes them.
7. **The session writes verdicts** by these tests and brings the owner only a verdict the tests
   leave unsettled.

### The owner's recorded direction

Each decision above was put to the owner as a question with a recommendation; their replies,
verbatim, with the round they were given in:

| Question as asked | Recommendation | Reply |
|---|---|---|
| Should each verdict be decided by these tests, in this order: (1) keeps our PR contracts, (2) keeps merge authority where our rules put it, (3) bills nothing, (4) works for every consumer's plan, (5) on a tie, prefer the built-in? | yes, these five tests in this order | "Yes go with recommendations" (round 2) |
| Should a session write each verdict itself by the five ordered tests, on your recorded direction, and bring you only a verdict the tests cannot settle? | yes, the session rules by the tests and escalates only a tie the tests leave open | "Go with recommendations, should we try them all in this session?" (round 3) |
| Should test results map to verdicts this way: a built-in that fails test 1 or 2 is `complementary` when it does a different job and `prefer-ours` when it does the same job; one that bills goes to you; one that passes tests 1-4 and does the same job is `prefer-native`, or `superseded` when ours adds nothing? | yes, this mapping | "go with recommendations, and Q24 - correct" (round 4) |
| Should a feature-gated built-in that every consumer can turn off still pass test 4, carrying the store's `gated` marker, and should tests 2 and 3 read each consumer's own settings rather than ours when a verdict changes a shipped plugin? | yes to both | "go with recommendations, and Q24 - correct" (round 4) |
| Should your verdict direction live in ADR 0137 in this repository, cited by each store row, instead of a row in the private owner-decisions record? | yes, ADR 0137 holds the direction | "go w/ recomendations" (round 5) |
| For a verdict that changes a shipped plugin, should all four tests read the consumer's own settings (its PR contract, merge rule, cost choice and plan), with this repository's rules used only for verdicts about this repository's own lanes? | yes, all four tests read the consumer's settings for shipped verdicts | "go w/ recomendations" (round 5) |
| Should a built-in that some consumers' plan lacks (a test 4 failure) be ruled on its job like any other surface, carrying the `gated` marker, with shipped routing falling back to ours where it is absent? | yes, rule it on its job with the `gated` marker | "go w/ recomendations, is there anything we can try here now?" (round 6) |
| On a test 1 or 2 failure (the built-in breaks the consumer's pull request contract or merge rule), should the verdict be `prefer-ours` when both do the same job, its required reason naming the failed test, and `complementary` when the jobs differ? | yes, the job decides | "go w/ recomendations, is there anything we can try here now?" (round 6) |
| For a shipped verdict, should a billed surface pass test 3 only where the consumer's settings opt in to billed surfaces, failing like tests 1-2 otherwise, with "billed: owner" kept for this repository's own lanes? | yes, the consumer's cost choice decides shipped verdicts | "go w/ recomendations, is there anything we can try here now?" (round 6) |
| Should the ADR count as the owner's recorded direction by quoting your verbatim interview answers, with their round numbers, as its decision text? | yes, the ADR quotes your answers verbatim with round numbers | "go w/ recomendations, is there anything we can try here now?" (round 6) |
| One committed verdict per pair, judged on the job only, with per-consumer conditions applied at run time; a same-job `gated` or `billed` surface caps at `prefer-native`, never `superseded`? | yes | "go w/ recommendations, confirmed" (design round 1) |
| Defer the billed marker and the billed opt-in key until the first billed row needs routing? | yes, defer both | "go w/ recommendations" (plan stage) |

Round 5's reply closed one gap as a test 4 failure being `complementary`; round 6 replaced that
with item 3's second bullet, because `complementary` means different jobs.

## Alternatives considered

- **(a) No fixed tests; judge each pair case by case.** Verdicts could not be checked against
  anything, and two sessions could rule one pair two ways. Not chosen.
- **(b) The direction as a row in the private owner-decisions record.** The store is public and
  could not cite it. Not chosen.
- **(c) One row per consumer profile.** Exact per consumer, but it multiplies rows and puts consumer
  specifics into what ships. Not chosen.
- **(d) A billed or plan-limited surface as `defer` until every consumer can use it.** It may never
  resolve. Not chosen.

## Consequences

- Every verdict a session writes cites this record in the row's `evidence`.
- `/ship` and `/steward` stay `defer` until the owner trials them on a pull request; the trial is
  tracked in its own issue.
- Recheck when a native surface's billing or plan availability changes, or when the store gains a
  verdict value or marker.
