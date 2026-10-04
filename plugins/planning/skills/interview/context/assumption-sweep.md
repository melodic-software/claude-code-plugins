# Assumption sweep

The sweep inventories what the contract would lock without the user having seen it, so each item
is asked, stated, or blocked before the confirmation gate.

## When

- `me` and `auto` runs with a register, once the frontier is empty and before the Step 3 register
  gate and confirmation gate. The `auto` Mixed path runs it after its residue round.
- Skipped when the run asked no question (no register exists) and in `lock`.
- After the answers to sweep rows land, sweep again over what those answers changed. Step 3 starts
  when a sweep adds no `open` row.

## Dispatch

A fresh-context (non-fork) sub-agent, so it does not inherit the reasoning that produced the
recommendations. Request any subagent type but `fork`. Verified 2026-09-27 against
[the subagents doc](https://code.claude.com/docs/en/sub-agents#how-forks-differ-from-other-subagents),
"How forks differ from other subagents" and "Turn fork mode on or off": a non-fork subagent
starts from "Fresh context with the prompt you pass", a fork from the "Full conversation
history", and a fork is spawned only when the `fork` subagent type is requested. Recheck when
that table changes what a non-fork subagent starts from, or when a request that names no type
can yield a fork. Hand it:

- the ledger: `## Constraint ledger`, `## Open-question register`, and the decision tree;
- every recommendation as asked, with its `Checked against:` line and `Commits you to:` parts;
- the composed artifacts the interview read: explore or research output, an existing
  implementation, an upstream Brief;
- the Brief draft, or the shared-understanding draft in a general session.

Withhold the rationale that sold each recommendation. The sweep checks what would be locked, not
why it was recommended.

## What it looks for

- **Undecided details:** a decision the draft relies on that no register row covers.
- **Hidden defaults:** a value the draft or a composed artifact fixes that the user never saw,
  including a recommendation part not listed under `Commits you to:`.
- **Contradictions:** two `answered` rows, or an answer and a `confirmed` constraint, that cannot
  both hold.
- **Unasked inherited constraints:** an `inherited` row the contract relies on with no register row.
- **Hedged and free-text rows:** every row whose resolution carries `hedged:`, and every
  `free-text:` row whose answer is hedged. List them for the Step 3 confirmation restate, which
  loop.md "Hedged flag" defines.

The acceptance-criteria coverage prompt is never a sweep item.

## Item shape

The sub-agent returns one line per item, numbered `S<N>` within this sweep:

```text
- S1 | hidden-default | decision | Q4 recommendation, retention window | depends: Q4, C2 | blocking: yes | hidden-default: yes
- S2 | contradiction | decision | Q3 and C1 | depends: Q3, C1 | blocking: yes | hidden-default: no
```

Fields:

- **id:** `S<N>`, contiguous within the sweep.
- **category:** `undecided`, `hidden-default`, `contradiction`, `inherited`, or `hedged`.
- **class:** `decision` (the user's call), `fact` (the environment answers it), `tenant` (a
  setting of the environment the work targets, confirmed by whoever owns it or read from a
  connected system that holds it), or `person` (only a
  named person other than the user can answer it).
- **source:** where the item was found: a row id, a recommendation, an artifact path and section.
- **dependencies:** the `Q<N>` and `C<N>` ids the item rests on.
- **blocking:** `yes` when the contract cannot lock without it.
- **hidden-default:** `yes` when a value was fixed without being asked.

## Disposition

You write the results, not the sub-agent, so register ids stay contiguous.
`S<N>` never reaches the register.

- **fact and tenant:** run the self-answer step first
  ([`self-answer.md`](../../../context/self-answer.md)), connected and connectable sources
  included. An item it answers is stated with its source tag and basis, with no row (loop.md
  "Self-answer gate"); one an unconnected system would answer joins the offer to connect. An
  item no source answers falls through to the next line.
- **decision, person, and an unanswered tenant or fact:** a register row at the next contiguous
  `Q<N>`, written `open` and
  asked in the next round with a recommendation. A `person` item the user cannot answer, and a
  `tenant` item when the user is not the setting's owner, are `deferred` to the Brief's
  `### Deferred questions` with its arbiter tag.
- **contradiction:** one row naming both sides, asked as a choice between them.
- **hedged:** no new row. The rows go to the confirmation restate.
- **Unattended:** an item that is the user's decision is `blocked` with **arbiter:
  USER-RESERVED**, per loop.md "Unattended path".

Any `open` row it adds returns the run to Step 2.
