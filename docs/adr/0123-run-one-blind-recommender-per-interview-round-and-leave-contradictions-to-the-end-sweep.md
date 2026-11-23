# Run one blind recommender per interview round and leave contradictions to the end sweep

- Status: accepted
- Date: 2026-11-22
- Related: [#17965](https://github.com/melodic-software/claude-code-plugins/pull/17965) (the
  change), [#17964](https://github.com/melodic-software/claude-code-plugins/issues/17964) (the
  need); owner interview, rounds 6 to 12 (Q31, Q36, Q39, Q43, Q52)

## Context

`/planning:interview`'s recommendations are drafted by the session that has heard every earlier
answer, so a recommendation can echo the user back to themselves instead of following the facts.
Contradictions between answers were checked twice: by a fresh-context pass before each round and
by the assumption sweep at the end of the interview. Each answer also now records the questions
it rests on (`depends::`), so a reopened answer marks every row built on it with `recheck::`.

The owner set the shape in round 8 (Q36, free text): "separate agents for blind recommendations and
contradiction checks, single responsibility; recheck against the over-verification guidance". The
recheck found that the current model prompting guidance treats extra verification steps as waste,
while the blind recommender is a bias guard, not a verification step. The owner then accepted
dropping the per-round contradiction pass (Q39, round 9) and running only the recommender each
round (Q52, round 12), both as recommended.

## Decision

1. **One blind recommender per round.** Once a round's decision questions are drafted, the main
   session dispatches `plugins/planning/agents/interview-recommender.md` once. It gets each decision
   question with its options unranked and its Context facts, the constraint ledger, the settled
   decisions with their answers and the self-answered facts. It gets none of the conversation and
   none of the session's own answers. It has read-only tools and inherits the session's model.
2. **Its answer is the recommendation.** When the main session's own draft differs, one `Second
   view:` line shows it. Settled decisions are inputs the recommender may depart from (Q43), and a
   departure shows as one `Departs from:` line. No `question_detail` level hides either line. A
   round with no decision question runs no recommender.
3. **No per-round contradiction pass.** Contradictions between answers are found by the end sweep,
   which reports every finding for the main session's disposition pass to filter, and by the
   `depends::` and `recheck::` marks a reopen writes.

The rule lives in `plugins/planning/skills/interview/SKILL.md` "One blind recommender drafts each
round's recommendations".

## Alternatives considered

- **(a) One fresh-context reviewer per round that drafts recommendations and checks
  contradictions.** No new agent, but one agent with two jobs. The owner chose separate
  responsibilities (Q36).
- **(b) Restore the per-round contradiction check as its own agent.** Catches a contradiction
  earlier, at one more call per round, against the over-verification guidance. Not chosen (Q39,
  Q52).
- **(c) Show recommendations only after the user answers.** Removes anchoring on the agent, but is
  slower and the user decides without the reasoning. Not chosen (Q31).
- **(d) Rely on `/planning:audit-answers` at the end.** Cheaper, but finds echoes late. Not chosen
  (Q31).

## Consequences

- Each round with a decision question costs one recommender call and no contradiction call.
- A contradiction between two answers can survive until the end sweep unless a `depends::` link
  connects them.
- With no Agent tool, the main session drafts the recommendation itself and shows no `Second
  view:` line.
