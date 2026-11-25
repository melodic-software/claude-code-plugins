# Routing by size and fog

Reference detail for the `## Routing by size and fog` section of `SKILL.md`. Read it at entry
and at every round boundary: it owns the entry gate's thresholds, the round-1 wayfind question,
the problems list, the round header's scope-check line, the bigger-than-you-thought check, what the handoff to `/planning:wayfind` carries, and the "this
is small, ship it" exit.

## Entry: diff size and retry cost, not behavior change

A change whose diff is quick to review and cheap to retry skips the interview (SKILL.md "What
this skill does NOT do"). Work that fails either test is interview-first,
and an effort too big and too foggy for one session is reached from here, never first
(`/planning:wayfind` sends a cold start back to this skill). When the interview is invoked on one, say so in one line and recommend
just doing it: build it, then review the diff and align on it there. The user can still ask for the
interview, and then it runs as usual.

Which stage or skill the work goes to next, and why, is route choice, and its one home is
`/session-flow:workflow`: its quick-change and foggy-effort on-ramps, and its pre-implementation
order. This file keeps only the interview's own triggers and
thresholds.

An effort plainly over its budget: run the scope cut in [`composition.md`](composition.md) "Scope
cut before wayfind" first, in round 1 when the request already shows it.

## Round 1: the request already names unknowns in several areas

When the opening request itself states unknowns across several separate areas (three or more, each
with something the user says is not yet known or decided, such as "not sure how billing, sign-in,
or the data migration should work"), round 1 carries one question recommending
`/planning:wayfind chart`, which charts those unknowns as a map of decision items. The interview
stays the entry either way:

- Ask it as a registered round-1 question in the whole question layout, worded so yes accepts ("Should this
  effort move to `/planning:wayfind chart` now?"), its Context naming each unknown area in the
  user's words. Round 1's other questions go out in the same message; never hold them for this
  answer, and never switch on your own. In an intake round it goes out instead as the one-line
  routing suggestion [`lookups.md`](lookups.md) "The intake round" shapes, still registered at
  ask-time, since an intake round shows a `My recommendation:` block only for the quality bar.
- Accepted: write the ledger as "The handoff to wayfind" below says, and name
  `/planning:wayfind chart` with the ledger path for the user to run.
- Declined: record the decline as the row's resolution and carry on with the rounds. Raise wayfind
  again only on the fog trigger or the confirmation trigger below.
- When the scope cut above also applies, it goes first and this question moves to round 2, after
  the cut's answer, counting only the areas the cut keeps.

Unknowns in two areas or fewer, or unknowns the request does not state, are not this trigger: fog
that surfaces during the rounds is the fog trigger's.

## Problems

The problems the work serves are agreed in round 1: from the intake answers, or from the request
when it states them. Write each to the ledger's `## Problems` section as
`- P<n> | <one-line problem> | proposed`, numbered from P1 in the order they were given, restate
them at the top of the next round, and mark each `agreed` once the user confirms it. Each question
registered after that carries `problem:: P<n>` for the problem it serves (loop.md "Register tags"),
and every line the user reads pairs the code with its words (`problem P2 (late invoices)`).

A problem set that will not fit one session goes to `/planning:wayfind chart` only through the
triggers below, which stay too big AND too foggy: the problem count is evidence for them, never a
trigger of its own.

## The scope-check line

Every round header, the intake round's included, carries one `Scope check:` line. Once round
`<N>`'s questions are drafted and before its file is written, take its ids and this line in one
call:
`bash "<plugin-root>/surface/round.sh" next-id --ledger <memory_dir>/<topic-slug>/interview-checklist.md --count <n> --round <N> --rounds-dir <memory_dir>/<topic-slug>`.
`<n>` is the round's new rows (SKILL.md, the `Q<N>` numbering paragraph). The first `<n>` output
lines are the new ids; the next line is `Scope check: <n> questions asked so far`, every register
row with this round's new rows counted in, and a `Wayfind:` line follows it when the fog trigger
below fired. Paste both into the round header as printed. The same call records the round's
counts as `round <n> | opened <a> | closed <s>` lines under the ledger's `## Round counts`,
rewriting a round's line on a rerun. On the page lane the call adds `--dir '<data_dir>'`. For a
round that adds no row, `round.sh scope-check` with the same `--round` and `--rounds-dir` prints
and records the same lines. With no Bash, count the same from the ledger by the rules of
`scope-check` in [`../../../surface/README.md`](../../../surface/README.md) and write the lines
yourself.

## Bigger than you thought? Check at every round boundary

After each reply is recorded and before the next round is written, answer one question: did this
turn out larger or foggier than it looked at entry? Wayfind has three triggers, the round-1
question above and the first and third below; the second recommends `/session-flow:workflow`:

- **Fog: two rounds running opened more than they closed → `/planning:wayfind chart`.** `round.sh`
  decides it from the ledger's `## Round counts`: when each of the last two rounds registered more
  new rows than it settled (answered, deferred, withdrawn or blocked), its `Scope check:` call
  prints the `Wayfind:` line, which goes in the round header as printed. One round is noise. This
  is the fog evidence wayfind's too-big AND foggy stop rule needs, so a recommendation to chart
  always rests on it.
- **Size alone: the context zone has worsened → `/session-flow:workflow`.** The session's
  context-usage report (the zone line the module injects, or its `mcp__context-usage__status`
  tool) puts the session in a worse zone than the one it reported at entry. Use only a report the
  harness already surfaced or that tool; do not poll your own context statistics, and write no
  token or percentage figure here, because the zone thresholds belong to context-usage. No report,
  or `unknown`, is not a trigger. With no fog trigger, this recommends routing the continuation
  through `/session-flow:workflow` (Step 5), not wayfind. When both hold, recommend wayfind.
- **At the confirmation: topics are left → suggest `/planning:wayfind chart`.** When the
  confirmation is written and the last round's `Later:` line was not empty, or a register row is
  `deferred` to an arbiter outside the pipeline skills (a person or team, not `/planning:design`,
  `/planning:plan` or `USER-RESERVED`), topics remain that this session cannot settle: one line
  before the confirmation's Next line names them and says `/planning:wayfind chart` would carry
  this ledger over. It is a pointer, not a question: the confirmation goes out as usual, and a
  reply asking for wayfind takes the handoff below.

On a fog or context-zone trigger, recommend its route to the user in one short block (the trigger
and its evidence, what it would carry over); never switch on your own. If neither fired, ask the
next round. After the user declines, raise it again only when it escalates: the zone worsens
further, or the other of those two triggers fires.

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
`/planning:wayfind chart` finds it, whether the user reaches it by `/clear` or, with
`session-flow` enabled, through `/session-flow:handoff`'s new-session delivery on the desktop app.

## Small after all: ship it

At any round boundary the user can say the work is small ("this is small, ship it"), and the
model can propose the same when the diff now looks quick to review and cheap to retry. The model's
proposal waits for the user's yes, because the remaining questions are the user's to drop.

On that yes, stop asking and close out through the normal gates; ship-it drops questions, never a
gate:

1. Move each `open` and `discussing` row to `deferred`, with the user's reply as its resolution, so the
   register gate passes without inventing an answer. Skip the assumption sweep: it exists to find
   more questions, which the user just declined; say so in the restatement, and tick the ledger's
   Step 2 exit box with `SKIPPED: ship-it`, since the `--procedure` check fails on an unchecked one.
2. **Step 3 still runs, confirmation gate included.** The yes to ship it drops the remaining
   questions; it does not confirm the shared understanding. Run the register gate and the
   `--procedure` check, restate with the register recap (the deferred rows visible in it), and get
   the user's confirmation.
3. **Step 4 as usual.** An engineering session writes the Brief: each deferred row goes under
   `### Deferred questions`, led by its `Q<N>` id, tagged **arbiter: USER-RESERVED** (the handoff
   skips `/planning:plan`, so no plan stage would resolve a `/planning:plan` tag). No later stage
   resolves these rows: the user dropped them, and the tag records that only the user re-raises
   one. The `--brief` cross-check must exit 0 before handing off. A `scope` run writes no Brief:
   it returns each deferred row as a `Deferred: Q<N> ... (arbiter: USER-RESERVED)` line in its
   `Scope decisions:` section. A general session writes the shared-understanding summary with the
   deferred rows listed.
4. Hand off by what the session produced, never to `/planning:plan`: engineering work that is not
   design-significant goes to implementation (`/implementation:implement`), design-significant
   work goes to `/planning:design` first (SKILL.md Step 5), a general session delivers its summary
   and stops, and a `scope` run returns to its caller. The handoff message lists each deferred
   row by its `Q<N>` id and question, because `/planning:plan`'s approval gate, the usual place a
   `USER-RESERVED` row comes back to the user, does not run on this path.
