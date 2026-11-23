# Set interview question detail with one three-level key over a full round file

- Status: accepted
- Date: 2026-11-22
- Related: [#17965](https://github.com/melodic-software/claude-code-plugins/pull/17965) (the
  change), [#17964](https://github.com/melodic-software/claude-code-plugins/issues/17964) (the
  need); owner interview, rounds 3 to 6 and 14 (Q15, Q16, Q21, Q53);
  [ADR 0075](0075-resolve-plugin-settings-through-one-four-layer-cascade-and-a-bound-convention-home.md)
  (the layers the key resolves through)

## Context

`/planning:interview` printed every question in one fixed layout, with no setting for how much of
it to show. A shorter layout risks hiding what the user accepts when they say yes. The interview's
UX review found that four per-field switches would give 16 combinations, some of them hiding
exactly that. `/planning:audit-answers` reads each question's Context from the saved round file,
so the file cannot shrink with the printed copy.

## Decision

The owner accepted the recommendation in round 6 ("I like all of your recommendations... still
reading") and confirmed it in round 14 (Q53).

1. **One key, `question_detail`, with values `full`, `standard` and `minimal`; default
   `standard`** (Q15, Q16). It is a planning plugin `userConfig` key
   (`plugins/planning/.claude-plugin/plugin.json`), documented in
   `plugins/planning/reference/config.md` beside `question_pacing`, and resolves through the same
   layers. A request in the session overrides it: "more Q<N>" prints one question in full, and
   "full round" prints the round in full.
2. **The round file is always full.** `round-<N>.md` holds the whole block, `Origin:`, `Basis:`,
   `Checked against:` and the `Source:` quote included. `round.sh show --level <level>` prints the
   round at the resolved level, and the interview pastes that output.
3. **What each level drops.** `standard` drops `Origin:`, `Basis:`, `Checked against:` and the
   `Source:` quote's body (its link stays), and puts each alternative on one line. `minimal` also
   drops `Context:` and `Source:` and prints an alternatives count.
4. **No level hides what the user accepts** (Q21): the recommendation and its reason, a reused
   literal value, `Withheld:`, `Discovery:`, `Second view:`, `Departs from:`, `Flips if:` and every
   `Commits you to:` part. The renderer and its tests enforce this.

## Alternatives considered

- **(a) Four switches** (`show_context`, `show_alternatives`, `show_origin`, `show_basis`). The
  finest control, but 16 combinations to test, some hiding what the user accepts. Not chosen (Q16).
- **(b) `full` as the default.** The most auditable, at about twice the length of `standard`. Not
  chosen (Q15).
- **(c) `minimal` as the default.** The fastest, but the user accepts reasons they never saw. Not
  chosen (Q15).
- **(d) A preset matching Matt Pocock's grilling skill.** A familiar look, but it carries no
  Context or sources, which breaks the interview's grounding rule. Not chosen (Q15).

## Consequences

- Detail is one choice for the user and one key to test, and `full` stays one setting or one
  request away.
- Downstream readers of the round file see the same content at every level.
- With no Bash, the interview prints the `standard` block itself by the same rules.
