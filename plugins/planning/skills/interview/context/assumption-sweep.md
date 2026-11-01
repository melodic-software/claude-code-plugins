# Assumption sweep

The sweep inventories what the contract would lock without the user having seen it, so each item
is asked, stated, or blocked before the confirmation gate.

## When

- `me` and `auto` runs with a register, once no open question remains on the frontier and before
  the Step 3 register gate and confirmation gate. The `auto` Mixed path runs it after its residue round.
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
- the Brief draft, or the shared-understanding draft in a general session;
- the ledger's session-shorthand glossary (loop.md "Session-shorthand glossary"), the project's
  domain-vocabulary file when Step 1 read one, and the names the user has used this session for
  the things in scope, so it can tell a coined name from an existing one and find the closest
  name the user already uses.

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
- **Coined terms:** a name, label or abbreviation in a recommendation, a `Commits you to:` part or
  a composed artifact that the session coined: the user did not introduce it, neither the codebase,
  the domain-vocabulary file nor an upstream artifact already uses it, and the session-shorthand
  glossary has no line for it. An accepted answer does not settle it: an "accept all" accepts the
  choice, not a name the user never saw defined. Its class is `decision`.
- **Unstated values:** a reference to an existing value (an email address, account,
  subscription, region, secret name, repository) whose literal value appears nowhere in the
  ledger, as in "alerts to the existing budget's address". Word it "Q<N> relies on <value> but
  never states it". An accepted answer does not settle it: the user accepted a value they never
  saw. Its class is `decision`.

The acceptance-criteria coverage prompt is never a sweep item ([`coverage-prompt.md`](coverage-prompt.md)).

## Item shape

The sub-agent returns one line per item, numbered `S<N>` within this sweep:

```text
- S1 | hidden-default | decision | Q4 recommendation, retention window | depends: Q4, C2 | blocking: yes | hidden-default: yes
- S2 | contradiction | decision | Q3 and C1 | depends: Q3, C1 | blocking: yes | hidden-default: no
```

Fields:

- **id:** `S<N>`, contiguous within the sweep.
- **category:** `undecided`, `hidden-default`, `contradiction`, `inherited`, `hedged`,
  `coined-term`, or `unstated-value`.
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
  item no source answers falls through to the next line. The F-line's basis quotes the source
  text that settles the item, with its file:line or URL: `package.json:14 "bullmq": "^5.1.0"`.
  The quote holds no `|`. An earlier session claim, or a decision you remember, is not a source,
  and an answer with no file:line or URL to quote (a connected tool's output) leaves the item to
  the next line.
- **Quote check:** before a fact-settled item counts as settled, dispatch a fresh-context
  (non-fork) sub-agent, as in "Dispatch" above, handing it only each such F-line's fact, quote and
  location. It re-reads each location and returns, per F-line, `confirmed` when the quoted text is
  there and states the fact, else `not-found`. This is how `/planning:audit-answers` checks
  answers: a validator that never saw the reasoning. A `not-found` item is not settled; it falls
  through to the next line as a register row.
- **decision:** never settled from facts, whatever the session believes was decided earlier.
  The self-answer step never resolves a decision (loop.md "Self-answer gate"), so a sweep's
  `decision` item always takes the next line.
- **decision, person, and an unanswered tenant or fact:** a register row at the next contiguous
  `Q<N>`, written `open` and
  asked in the next round with a recommendation. A `person` item the user cannot answer, and a
  `tenant` item when the user is not the setting's owner, are `deferred` to the Brief's
  `### Deferred questions` with its arbiter tag.
- **contradiction:** one row naming both sides, asked as a choice between them.
- **hedged:** no new row. The rows go to the confirmation restate.
- **coined-term:** a register row asking the user to accept or rename the term, with the closest
  existing name in the user's vocabulary as the recommendation, and naming the existing term it
  overlaps. With no existing name close to it, recommend keeping the term, defined in one line. An
  accepted or renamed term is written to the glossary; a rename also replaces the term in the
  draft and in the resolutions of the rows that carry it, and the next sweep covers those rows.
- **unstated-value:** a register row asking the user to confirm the literal value, whoever owns
  it; this item never takes the fact-and-tenant line above. Run the self-answer step to find a
  candidate, and recommend it with its literal value and where it was read; finding the value
  never replaces the row. With no candidate, ask the question withheld. When the user does not
  own the value, the row is `deferred` to the Brief's `### Deferred questions` with its arbiter
  tag. The confirmed literal is written into the resolution of the row that relied on it.
- **Unattended:** an item that is the user's decision is `blocked` with **arbiter:
  USER-RESERVED**, per loop.md "Unattended path".

Any `open` row it adds returns the run to Step 2.

**Record every item.** Before dispatching a sweep, write `- sweep <M> | register through Q<N>`
into the ledger's `## Assumption sweep` section, where `sweep <M>` counts the sweeps from 1 and
`Q<N>` is the register's last row. Then write each item there as
`- S<N> | sweep <M> | <category> | <class> | <source> | <disposition>`. The disposition is one of: the `Q<N>` register row the item became, or the
existing row a hedged item points at; the `F<N>` line that settles it; or `deferred: <where>` for
an item settled outside the register (a hedged item's `deferred: confirmation restate`). Only a
hedged item points at a row its source names; every other item's `Q<N>` is the new row it became,
above that sweep's `register through` row.
A `decision`, `person` or `unstated-value` item never takes an `F<N>`. A sweep that returned nothing records `- none`. Then tick the Step 2 exit box. When the sweep is skipped,
tick the box with `SKIPPED: <reason>`. The `--procedure` gate fails on an unchecked Step-exit box,
an item with no disposition, a `decision`, `person` or `unstated-value` item without a `Q<N>`, and an `F<N>` whose
basis quotes no source with a file:line or URL ([`check-open-questions.sh`](../../../scripts/check-open-questions.sh)).
The section also tells a later session which items were settled without the user.

The round that asks these rows is a **sweep round**. On the page, post it with
`"meta": {"kind": "sweep"}` on `add-round`, and give each question that weighs earlier answers a
`reconciles` list of their `Q<N>` ids; the page labels the round `Sweep: reconciling earlier
answers` and shows each listed answer beside the question ([`surface.md`](surface.md) "A round").
In the terminal lane, open the round with that label and quote each listed earlier answer under
its question.

## Pre-round contradiction pass

Before every round after the first is asked inline or posted with `add-round`, check the draft
round against what the user already answered, so a conflict is caught before the user sees it
rather than at the next sweep.

- **Dispatch:** a fresh-context (non-fork) sub-agent, as in "Dispatch" above. Hand it the draft
  round (each question with its recommendation, `Checked against:` line and `Commits you to:`
  parts) and every `answered` register row with its resolution, plus the `confirmed` constraint
  rows. Withhold the rationale, as above.
- **Scope:** only the **Contradictions** category of "What it looks for", read with the draft
  round's recommendations standing in for answers: a recommendation that cannot hold beside an
  `answered` row or a `confirmed` constraint. No other category runs here; the sweep still runs
  once no open question remains on the frontier.
- **Return:** one line per conflict in the "Item shape" above, category `contradiction`, with the
  draft question and the earlier row as its dependencies; nothing when there is none.
- **Disposition:** fix each in the draft before posting. A conflict with a `confirmed` constraint
  is fixed by revising the recommendation so it holds, citing the constraint on its
  `Checked against:` line. A conflict with an answered row is fixed the same way, or by replacing
  the question with one that names both sides and lists that row's `Q<N>` in `reconciles` (only
  question ids go there). A draft conflict never becomes a register row of its own; the revised
  question takes its place.
