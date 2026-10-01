# Deferred interview page work

Behaviors the interview page does not build, each marked build (with its issue), park, drop, or open when the decision is still pending. Park keeps the entry for a later decision and is the reversible choice.

Reason for parking: the owner's scope guard, "we want these to be, in most cases, kind of short-lived, on the fly. We ingest them and then move on". Sessions are short-lived and the page is not a durable store.

## Decision gaps from the commitment rules

| Entry | Decision |
|---|---|
| 1. Addendum wording lint: whether the coined-term check becomes a script check | Open: awaiting the owner |

## Deferred behaviors

| Entry | Decision |
|---|---|
| "Accept all and have agents check them": a page button that hands a round to `/planning:audit-answers` | Build: #5472 |
| A hidden-tab title badge | Build: #5473 |
| Mermaid rendering, which needs a vendored renderer because the page's CSP allows no network source | Open: the renderer size is undecided, #5474 |
| Composer extras: attachments (paste or drop images and video), link detection, markdown with code highlighting, slash autocomplete for skills and `@` for question ids, dragging a note onto a question | Park |
| Hold sends; typed debounce | Park |
| Server as sole writer of both files; SSE deltas with `Last-Event-ID`; a server idle exit | Park |
| The stale cascade (automatic transitive re-staling) | Park |
| Size-signal line and split proposal cards on the page | Park |
| A minimum text size inside SVG | Park |
| Monitor, plugin-monitor and channel wake rungs | Park |
| A "What am I assuming?" button | Park |
| A one-way/two-way door tag | Park |
| An off-screen reply toast with a jump link | Park |
| A SQLite store | Park |
| Image export | Park |
| The self-improvement loop (the interview skill improving the interview process) | Park |
| Several sessions each taking a group | Park |
