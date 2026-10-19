# Problem framing: establish the problem before any solution

Every planning skill that shapes work runs this procedure before it proposes, plans or designs a
solution: what is going wrong, who has it, how big it is, the evidence that it is real, and the
size of the work, kept as separate concerns. The agent states its understanding; the human
confirms it.

## Problem fields

The Brief's `### Problem` records each field as one line:

- **Gap:** what is going wrong, or what is missing, stated without a solution.
- **Who / how many:** the people or systems that have the problem, and how many.
- **Frequency:** how often it happens.
- **Trend:** whether it is growing, steady or shrinking.
- **Cost:** what it costs when it happens: rework, failures, lost time or money, risk.
- **Evidence:** what shows the problem is real, each item with its rating (next section).

A field with no evidence reads `unknown` in an engineering Brief. Never fill one from a guess.

## Evidence rating

Each evidence item, and each inferred problem, carries exactly one rating:

- **observed:** a cited artifact or measurement (a log, a metric, an incident, a failing test, a
  `file:line`).
- **reported:** a person says so, with no artifact behind it.
- **inferred:** the agent's own reading of the request or the code.

## Restate and confirm

Before the Brief is written, in every action, the agent restates the problem in one line and gets
the human's yes. The problem line opens the interview's existing restatement; the rest of the
restatement follows it. A no, or a correction, revises the problem and restates again. Under
`lock` the confirmation is one question, recorded as a register row, so the register gates run on
the Brief.

## Prescribed solution

A request that names a solution and no problem ("add a retry wrapper") gets its problem worked
back out: what failure or gap would this solution fix? State that problem with its evidence
rating, then ask one question: rethink the approach against the problem, or accept the prescribed
solution. An attended run always asks, however obvious the problem looks. A request that states
its problem is restated and confirmed, and gets no rethink-or-accept question.

## Artifact with history

When the request concerns an existing artifact whose problem lives in its history (a mechanism,
a workaround, a design choice), recommend `/discovery:trace-intent` when it is installed to
recover the problem. Otherwise work back from the evidence in-session: the commits, pull requests,
issues and docs that introduced it. Either way, rate what you recover.

## Work size

The Brief's `### Work size` records four fields:

- **Appetite:** how much the human is willing to spend on this work. It is the human's budget,
  not an estimate; ask for it, never derive it.
- **Size:** how big the work is.
- **Uncertainty:** how much of the work is not yet known.
- **Split signals:** what suggests the work should be several pieces, and whether that was acted
  on.

Appetite, size and uncertainty each take one level from the resolved `work_size` setting, named
with its one-line description. The defaults:

| Dimension | Level | Description |
|---|---|---|
| appetite | Small | A contained change the human will spend little on. |
| appetite | Medium | A real piece of work the human will fund with some care. |
| appetite | Large | A major investment the human accepts. |
| size | Small | One focused change with few moving parts. |
| size | Medium | Several coordinated changes inside one deliverable. |
| size | Large | Too big for one deliverable: split it. |
| uncertainty | Known | The approach and its unknowns are understood. |
| uncertainty | Knowable | The open points can be settled by looking. |
| uncertainty | Unknown | The open points need experiment or discovery. |

An unassessed field reads `not assessed`. The section has no effort, complexity, model or
performer field. A tracker's own size values are used only once the work-items plugin exposes a
size-value reader (https://github.com/melodic-software/claude-code-plugins/issues/8324); until
then the resolved setting is the only source.

## Large size

The last level of the resolved `size` dimension means split, whatever it is named. Recommend
`/planning:wayfind` or `/work-items:decompose` when either is installed and enabled. Otherwise
advise the split in-session: name the pieces and their order. The split is a recommendation,
never forced; the human may keep the work whole, and the Brief records that under split signals.

## Unattended

A run with no human to answer still writes the problem. `### Problem` opens with
`- Status: unconfirmed`. The confirmation, and any rethink-or-accept question, is a `blocked`
register row with arbiter USER-RESERVED, under rung 3 of the interview's existing unattended
ladder (`../skills/interview/context/loop.md` "Unattended path"). The Brief still locks, and the
run names the blocker in its output.

## Pre-confirmed

When the resolved `pre_confirmed_label` is present on the item and the item states its problem,
the problem counts as confirmed: `### Problem` carries no unconfirmed status and no confirmation
row is written. If the item also prescribes a solution, that counts as accept; record the
inferred problem and the prescribed solution under `### Captured assumptions`. With the setting
unset there is no pre-confirmation.

## Time units

No estimate or budget of work is stated in hours, days or weeks unless `time_units` resolves
true; use the `work_size` levels instead. Practice cadence ("integrate at least daily") and
measurement windows ("within 30 days of launch") are not estimates and are written as needed. A
time budget the user states is kept in the user's words.

## General sessions

A non-software interview's summary opens with the problem, in the same fields, and carries work
size scaled to the decision's stakes and reversibility: a small, reversible choice gets a line, a
costly or irreversible one gets each field. Omit a field that means nothing for the subject
rather than writing `unknown`.

## Settings

`time_units`, `pre_confirmed_label` and `work_size` resolve per
[`../reference/config.md`](../reference/config.md), and the run writes one report line per key
naming its value and the layer that supplied it. A `work_size` dimension set in the repository
file replaces that dimension's default as a whole; levels are never merged across layers.
