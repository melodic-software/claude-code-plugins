# Interview page backlog after V1

Recorded backlog for
[#4653](https://github.com/melodic-software/claude-code-plugins/issues/4653):
what the V1 SPEC (section 11, Deferred) and the #4455 merge gate left after
#4547 and #4561. This file is the tracked copy of that list. The local SPEC
folder named in #4653 is retired.

**Claim:** each row below is build, drop, or park as written. Items that make
the page a durable store stay parked. Hedged-kind and the register gate wait
on #4611. No page work from this record.
**Basis:** #4653 body (suggested defaults, SPEC section 11, prior operator
answers). Origin/main: `hedged` is absent from `round.py`, `exporters.py`, and
`index.html`; `index.html` sets a static `document.title`; #4611 is open.
Operator 2026-09-24 Q6 (accepted): sessions are short-lived and export into
the ledger, Brief, and design threads; "we might as well be building our own
giant app" is the rejected direction. Store Q7: JSON files now, SQLite only if
sessions grow large.
**As of:** 2026-09-28.
**Recheck:** #4611 lands a ledger grammar, or an operator unpark names one
build row as its own issue.

## Decision gaps from the commitment rules

| Item | Decision | Notes |
|---|---|---|
| Hedged decision kind on the page | Build after #4611 | Skill records a hedged reply; the page has no `hedged` state. Export as its own resolution with the condition text. |
| Register gate vs unticked commitments | Build after #4611 | Exported register carries confirmed commitments only. Gate rule: an accepted or hedged row with an unticked commitment grades `open` in `lock`. |
| Addendum wording lint (coined-term half) | Park | Stays a model-side instruction (recorded SPEC departure). Not a script check until a coined-term false-positive lands on main. |

## SPEC section 11 deferred behaviors

| Item | Decision | Notes |
|---|---|---|
| Composer: attachments (paste or drop images and video) | Park | Giant-app direction; CSP has no network source. |
| Composer: link detection | Park | Same. |
| Composer: markdown with code highlighting | Park | Operator asked (J6); still a durable-editor feature. Reopen with a bounded highlight slice, not a full composer. |
| Composer: slash autocomplete for skills and `@` for question ids | Park | Operator asked (J6); same as highlighting. |
| Dragging a note onto a question | Park | |
| "Accept all and have agents check them" | Build | Page action that posts one event the skill routes to `/planning:audit-answers`. Own issue after this record. |
| Hold sends; typed debounce | Park | Optional toggle in J3; not needed for short-lived sessions. |
| Server as sole writer of both files | Park | V1 split is load-bearing. |
| SSE deltas with `Last-Event-ID` | Park | |
| Server idle exit | Park | `server.py` has none; lease expiry already frees a dead watcher. |
| Stale cascade (automatic transitive re-staling) | Park | |
| Size-signal line and split proposal cards on the page | Park | Skill rule R-B ships; page cards would be a second UI. Settings count checkpoint stays off by default (J6). |
| Mermaid rendering | Park | Needs a vendored renderer (`test_exporters.py` CSP: no network source). Size cost is an operator call. |
| Minimum text size inside SVG | Park | Tied to Mermaid. |
| Monitor, plugin-monitor, and channel wake rungs | Park | Q4: channels were not viable (research preview, idle-wake bug). Long-poll watcher is the mechanism. |
| "What am I assuming?" button | Park | #4561 covers assumption gaps in the skill. |
| One-way / two-way door tag | Park | |
| Hidden-tab title badge | Build | Small; `index.html` sets a static title. Own issue. |
| Off-screen reply toast with a jump link | Drop | #4547's updated notice with Go covers it. |
| Image export | Park | Durable-store direction. |
| SQLite store | Park | Q7: JSON now. Q6 scope guard. |
| Self-improvement loop | Park | The interview skill improving the interview process. |
| Several sessions each taking a group (SPEC 2.5) | Park | V1: one watcher per data dir through a lease (Q5, built). |

## Sequencing

- Hedged kind and the register gate share one follow-up after #4611. Do not
  start them while the ledger grammar is still open.
- "Accept all" and the hidden-tab badge are independent scoped issues. File
  them when someone implements; this record does not open them.
- Parked rows stay here. Do not re-litigate them without an operator unpark.
