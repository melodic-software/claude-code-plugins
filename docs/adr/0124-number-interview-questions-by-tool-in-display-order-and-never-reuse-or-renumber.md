# Number interview questions by tool in display order and never reuse or renumber

- Status: accepted
- Date: 2026-11-22
- Related: [#17965](https://github.com/melodic-software/claude-code-plugins/pull/17965) (the
  change), [#17964](https://github.com/melodic-software/claude-code-plugins/issues/17964) (the
  need), [#7541](https://github.com/melodic-software/claude-code-plugins/issues/7541) (the
  renumbering bug and the owner's ruling); owner interview, rounds 5, 6 and 14 (Q20, Q27, Q53)

## Context

`/planning:interview` question ids (`Q<N>`) are cited across the ledger, the round files, the
Brief and later skills, so a changed id breaks every reference to it. No tool picked the next id:
the model chose it by hand. In #7541, ids ran 1 to 200 and then jumped to 500, and a range
"reserved above Q500" was later renumbered by the page lane's `sync-ledger`, breaking cross-file
references. The owner ruled on #7541 on 2026-10-17: "Keep ids (do not refuse)." The register gate
also refused any gap in ids, while the page exporter kept them.

## Decision

The owner accepted the recommendation in round 6 ("I like all of your recommendations... still
reading") and confirmed it in round 14 (Q53). The plan added the gap-line writer on 2026-11-21
with the owner's "go w/ recommendations".

1. **One `Q` sequence per topic**, with no number ranges and no type prefixes.
2. **A tool assigns every new id.** `round.sh next-id` (`plugins/planning/surface/round.py`) prints
   the highest id in the ledger, and in the page data folder when given, plus 1. Ids are assigned
   in the order the round shows its questions. An id is never picked by hand, reused, used to fill
   a gap, or renumbered.
3. **Every reader keeps the id.** The page exporter keeps the number each row already has and
   numbers only ids the ledger never held.
4. **Gaps are declared.** The register gate (`plugins/planning/scripts/check-open-questions.sh`)
   accepts a gap only where a `- gap | Q<a>-Q<b> | <why>` line declares it, and still fails on an
   undeclared one, since a row deleted after it was written leaves the same gap. `export-ledger`
   and `sync-ledger` write that line for ids no row ever held.
5. **Question type is a field.** A discovery question carries `kind:: discovery` in its row
   instead of a prefix.

## Alternatives considered

- **(a) Type prefixes per kind (`T`, `D`).** The type shows in the id, but ids collide across
  kinds, and no standard defines such prefixes. Not chosen.
- **(b) Number ranges per topic.** Lets parallel sessions number without clashing, but ranges are
  what broke in #7541. Not chosen.
- **(c) Let the gate accept every gap.** Removes the conflict with the exporter, but loses the only
  file-based check against a deleted row. Not chosen.

## Consequences

- An id seen once stays valid for the life of the ledger, in every file that cites it.
- A stray high id is not repaired: the sequence continues above it, and the range below it is
  declared as a gap.
- With no Bash, the model takes the highest number among the rows and the high ends of the gap
  lines, and counts up from it.
