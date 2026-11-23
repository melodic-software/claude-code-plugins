# Triage every interview unknown before round 1 and ask discovery questions first

- Status: accepted
- Date: 2026-11-22
- Related: [#17965](https://github.com/melodic-software/claude-code-plugins/pull/17965) (the
  change), [#17964](https://github.com/melodic-software/claude-code-plugins/issues/17964) (the
  need); owner interview, rounds 5, 6 and 14 (Q13, Q23, Q53);
  [ADR 0122](0122-ask-discovery-questions-open-and-recommend-only-on-decision-questions.md)
  (the discovery question kind)

## Context

`/planning:interview` used to run its deep lookups (`/discovery:explore`, `/discovery:research`)
after the Brief locked, so a fact found while planning overturned answers the user had already
given. In that interview one recommendation flipped after a lookup, and an answer had to be
reopened. Four files gave four different rules for when explore and research run: the interview's
`SKILL.md` and `context/handoff.md`, and the session-flow workflow's `steps.md` and
`pre-implementation-order.md`.

The owner asked for this in round 5 (Q13): "any questions whose answer could change based on
in-flight exploration and research validation? I just don't want to create wasted effort." Two
studies the interview's research turned up (both preprints) back it. Splitting "find what is
unspecified" from "do the task" closed most of the gap to fully specified tasks (Edwards and
Schuster). Goal clarification loses nearly all its value after 10% of execution (Gulati et al.).

## Decision

The owner accepted the recommendation in round 6 ("I like all of your recommendations... still
reading") and confirmed it in round 14 (Q53).

1. **Gap triage before round 1.** Every unknown the task depends on is sorted into exactly one
   kind: a lookup (a fact a source can answer, never asked), a discovery question (what only the
   user knows), or a decision question (a choice with a live alternative, asked once the facts it
   rests on are in).
2. **Lookups start before round 1 is sent**, so they run while the user answers it. Each lookup
   skill runs at most one dispatch at a time. Lookups for one skill go in one brief.
3. **Round 1 is the intake round**, asking only discovery questions. Decision questions wait for
   round 2. When the triage leaves no discovery question, there is no intake round, and round 1 is
   the first decision round.
4. **A question a running lookup could change is held** until the lookup returns. Every other
   question is asked now.
5. **One home.** The triage, the intake round, the lookup rule and the hold rule live in
   `plugins/planning/skills/interview/context/lookups.md`. The interview's other files link to it,
   and the two session-flow files name `/planning:interview`'s rule instead of stating their own.
   The interview routes no explore or research pass after the Brief.

## Alternatives considered

- **(a) Keep lookups after the Brief, as `handoff.md` said.** It starts faster, but answers get
  reopened when planning finds a fact the interview did not have. Not chosen.

## Consequences

- Round 1 can go out while lookups are still running, and only the questions those lookups feed
  are held.
- A fact that still contradicts an answer later reopens that answer under its own number (`round.sh
  reopen`), so a missed lookup costs a recheck, not a silent wrong answer.
- Design and plan still run their own lookups when their questions need one.
