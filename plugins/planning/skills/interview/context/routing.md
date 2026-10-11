# Routing by size and fog

Reference detail for the `## Routing by size and fog` section of `SKILL.md`. Read it at entry
and at every round boundary: it owns the entry gate's reason, the bigger-than-you-thought check,
what the handoff to `/planning:wayfind` carries, and the "this is small, ship it" exit.

## Entry: diff size and retry cost, not behavior change

A change whose diff is quick to review and cheap to retry skips the interview (SKILL.md "What
this skill does NOT do"): when the diff is tiny, a wrong build costs almost nothing, so aligning on
the diff after it exists beats aligning before it. Work that fails either test is interview-first,
and an effort too big and too foggy for one session is reached from here, never first
(`/planning:wayfind` sends a cold start back to this skill).

## Bigger than you thought? Check at every round boundary

After each reply is recorded and before the next round is written, answer one question: did this
turn out larger or foggier than it looked at entry? It is bigger when either trigger holds:

- **The context zone has worsened.** The session's context-guard report (the zone line the module
  injects, or its `mcp__context-guard__status` tool) puts the session past its best zone. Use only
  a report the harness already surfaced or that tool; do not poll your own context statistics, and
  write no token or percentage figure here, because the zone thresholds belong to context-guard.
  No report, or `unknown`, is not a trigger.
- **More branches opened than closed.** Count the register: this round's new `open` rows against
  the rows it moved to a terminal status. Two rounds running with more opened than closed is a
  trigger; one is noise.

On a trigger, recommend `/planning:wayfind chart` to the user in one short block (the trigger and
its evidence, what it would carry over); never switch on your own. If it is not a trigger, say
nothing and ask the next round.

## The handoff to wayfind

When the user accepts, the handoff carries everything this interview already holds, so nothing is
asked twice. Wayfind's chart step reads the ledger
(`<memory_dir>/<topic-slug>/interview-checklist.md`), so everything goes there before the handoff,
where a `/clear` between the two skills cannot lose it:

- answered rows: decisions so far;
- `open`, `deferred` and `blocked` rows: candidate decision items;
- the `## Constraint ledger`: the constraints the user stated;
- the `## Starting point` section: the user's starting-point disclosure from intake. When the
  ledger has none yet, write it now, one line in the user's words or a faithful paraphrase;
- the session-shorthand glossary.

The recommendation block names the ledger path, so a fresh session that runs
`/planning:wayfind chart` finds it.

## Small after all: ship it

At any round boundary the operator can say the work is small ("this is small, ship it"), and the
model can propose the same when the diff now looks quick to review and cheap to retry. The model's
proposal waits for the operator's yes, because the remaining questions are the operator's to drop.

On that yes, stop asking and close out through the normal gates; ship-it drops questions, never a
gate:

1. Move each `open` row to `deferred`, with the operator's reply as its resolution, so the
   register gate passes without inventing an answer. Skip the assumption sweep: it exists to find
   more questions, which the operator just declined; say so in the restatement.
2. **Step 3 still runs, confirmation gate included.** The yes to ship it drops the remaining
   questions; it does not confirm the shared understanding. Run the register gate and the
   `--procedure` check, restate with the register recap (the deferred rows visible in it), and get
   the user's confirmation.
3. **Step 4 as usual.** An engineering session writes the Brief: each deferred row goes under
   `### Deferred questions`, led by its `Q<N>` id, tagged **arbiter: USER-RESERVED** (the handoff
   skips `/planning:plan`, so no plan stage would resolve a `/planning:plan` tag), and the
   `--brief` cross-check must exit 0 before handing off. A general session writes the
   shared-understanding summary with the deferred rows listed.
4. Hand off to implementation (`/implementation:implement`), not to `/planning:plan`.
