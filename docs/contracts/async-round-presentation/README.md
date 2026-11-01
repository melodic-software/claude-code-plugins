# Async round presentation: the latest message holds every open item

A skill can show the user open items (questions, decisions, findings that wait on a choice) and
also dispatch async work: sub-agents, background tasks, lookups. That work can return after the
items are shown and before the user answers. This contract owns what the next message shows.

## The rule

When a skill has presented open items and dispatched work returns before the user answers, the
next message that presents anything ends with one block that restates every open item in full:
the question, its options, and the recommendation with its basis. The block marks each item the
returned work changed.

- **An item that depends on a pending result may be held.** It stays out of the block until the
  result lands; the block may name it in one line as waiting.
- **A status line while waiting is fine.** A message that only reports progress (a return touched
  no open item, work is still running) presents nothing, so it needs no block.
- **A partial set is never the last word.** A message that shows the changed item in full and
  points back to an earlier message for the rest breaks this rule.

## Why

The user reads the latest message. A pointer to an earlier block makes them scroll back to
rebuild the open set, and with several returns that set spreads across several messages, so an
item can go unanswered because it was never in view. A full restate costs length; the cost of a
pointer is an answer given against a set the user could not see whole.

## What this does not require

The rule does not hold a round until every dispatch drains. Items that do not depend on pending
work are still asked at once, so the session is not serialized behind its slowest lookup. Only
the items that need a pending result wait for it.

## Who is bound

Any skill that presents open items for the user's answer while its own dispatched work can still
return. A bound skill cites this file by its repository path, `docs/contracts/async-round-presentation/README.md`
in the marketplace, rather than restating a narrower rule. Adopters:

- `/planning:interview`: `plugins/planning/skills/interview/context/loop.md` "Out-of-band drift",
  with its pointer in the skill's `SKILL.md`.
- `/discovery:research`: `plugins/discovery/skills/research/SKILL.md` "Outcome gate (run before
  presenting)".
- `/discovery:explore`: `plugins/discovery/skills/explore/SKILL.md` "Outcome gate (before
  EXPLORE.md handoff)".
- `/review:fanout`: `plugins/review/skills/fanout/SKILL.md` "Step 2: Normalize".
- The [recommendation-basis](../recommendation-basis/README.md) re-emit shape defers to this
  contract when dispatched work moved a recommendation.

## Format changes

This contract carries no version. A change to the rule updates every adopter in the same pull
request.
