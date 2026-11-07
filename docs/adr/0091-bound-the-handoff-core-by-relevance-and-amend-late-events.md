# Bound the handoff core by relevance and amend late events

- Status: accepted
- Date: 2026-11-07
- Supersedes: decision 6 of
  [ADR 0084](0084-ship-handoff-shape-3-on-measured-size-and-leave-accuracy-to-the-resume-eval.md)
  (leave the core's growth unbounded)
- Related: [#13847](https://github.com/melodic-software/claude-code-plugins/issues/13847); owner
  decisions Q1-Q3,
  [2026-11-07](https://github.com/melodic-software/claude-code-plugins/issues/13847#issuecomment-6703829081)

## Context

ADR 0084 decision 6 left Original goal and Direction changes unbounded until accuracy runs that
never ran. At hop 46 of one real chain they held 21,048 and 21,418 bytes, 3.3 times the 16.4 KB
the ADR projected, and a near-cap core pushed a writer to drop in-force rules (#13847). Open
questions and Decisions in force are rewritten every hop with no carry check, so an unanswered
question can disappear between hops. And nothing folds an event that arrives after the handoff
is written into it: the reference text said the handoff "is not amended later by default".

The owner asked for handoffs that lose nothing, hold only what the next session needs now, and
take in late events (owner, 2026-11-07).

## Decision

1. **Keep by relevance, account for every move.** The goal quote, intent, vision, opening ask,
   and every amendment or Direction-changes line still in force stay verbatim. An entry that is
   superseded or done leaves the hot file only when this hop's file lists it verbatim under
   `## Retired goal amendments` or `## Retired direction changes` with a reason. An instruction
   that still binds is first codified (a rule, an instruction-file line, or an owner-decisions
   row), then retired with a pointer to it. `save_point.py validate` fails an entry that is in
   neither place. An amendment unit with any still-binding clause stays whole or is codified first;
   units are never split.
2. **Ids for Open questions and Decisions in force.** `[Q<n>]` and `[D<n>]` ids with monotonic
   frontmatter floors carry the same retire-with-reason check as rule ids. Observations and
   Completion criteria stay free-form.
3. **Retirement is a script operation.** `fill` and `amend` take references (`[R|Q|D<n>]`,
   `[h<k>]#<i>`, `amendment#<i>`) and copy the bytes themselves; the hot file carries a pointer to
   each retire listing forward.
4. **Amend late events.** `save_point.py amend` replaces written sections, may rewrite the
   `Next:` lines and raise id floors, appends the replaced text to this hop's file, re-validates
   and prints the resume prompt again. A hop file becomes append-only through `amend` instead of
   never edited. The handoff skill checks each event that arrives after emit and until `/clear`
   or a successor `new`, and runs `amend` when one changes a section.

## Alternatives considered

- **Keep the newest N entries by count.** Mechanical and easy to test, but it can hide an old
  amendment that still binds. Rejected by the owner.
- **Keep everything and accept UNVALIDATED.** Nothing moves, and the file keeps growing.
- **Owner-written summaries of older entries.** Needs the owner at every hop; published studies
  found summarized history no better than retained raw history.
- **Hand edit, then validate, then emit, for late events.** No new code, but the replaced text is
  lost unless copied by hand.

## Consequences

- Size stays the writer's judgment of relevance, checked for losslessness by `validate`; a wrong
  relevance call is recoverable from the hop file the pointer names.
- `amend` never blocks on a size finding, so a late event is never lost to the cap.
- The resume eval reruns on this change, as ADR 0084 requires, with two cases that grade the new
  read path: a writer keeping a still-binding amendment, and a reader answering from a retired
  entry.
