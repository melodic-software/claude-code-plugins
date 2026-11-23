# Ask discovery questions open and recommend only on decision questions

- Status: accepted
- Date: 2026-11-22
- Related: [#17965](https://github.com/melodic-software/claude-code-plugins/pull/17965) (the
  change), [#17964](https://github.com/melodic-software/claude-code-plugins/issues/17964) (the
  need); owner interview, rounds 5, 6 and 14 (Q21, Q22, Q53);
  [ADR 0121](0121-triage-every-interview-unknown-before-round-1-and-ask-discovery-questions-first.md)
  (where the two kinds are sorted)

## Context

`/planning:interview` put a recommended answer on every question, including the ones that ask the
user what the problem is, why it matters and who it is for. Showing a recommended answer pulls
people toward it. The elicitation research the interview ran reported that the cognitive
interview, The Mom Test and Teresa Torres's interviewing all ask for past facts, not preferences.
The skill already withheld recommendations at the idea stage, so the rule existed for one case
only.

## Decision

The owner accepted the recommendation in round 6 ("I like all of your recommendations... still
reading") and confirmed it in round 14 (Q53).

1. **A discovery question** asks what only the user knows: the problem and why, who it is for, the
   scope, where they start, where it heads. It is asked open: its Context block, then one
   `Discovery: <what the answer settles>` line in place of the recommendation, with no
   alternatives and never on a card. Its register row carries `kind:: discovery`, and no
   accept-shorthand resolves it.
2. **A decision question** is a choice with a live alternative and always carries a
   recommendation, or a `Withheld:` line naming the evidence that would settle it. A register row
   with no `kind::` tag is a decision question.
3. **The round-file check enforces it.** `plugins/planning/scripts/check-round-codes.sh` fails a
   question block that has none of `My recommendation:`, `Withheld:` or `Discovery:` (or, in the
   product action, `Strong answer:`).

The rule lives in `plugins/planning/skills/interview/SKILL.md` "A discovery question carries no
recommendation".

## Alternatives considered

- **(a) A recommendation on every question, as before.** Faster to answer, but it anchors the
  user's own problem statement on the agent's. Not chosen.

## Consequences

- The user states the problem in their own words before seeing any of the agent's.
- A choice a discovery answer leaves open becomes a decision question in the next round.
- A decision question shown with no recommendation is caught on disk before the round is sent,
  which nothing caught before.
