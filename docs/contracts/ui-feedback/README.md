# UI feedback: in-page notes on non-final UIs

A skill that renders a non-final UI (a mockup, a prototype, a design exploration) lets the person
pin notes to it and set its controls from the page. This contract owns the parts that do it: a
host page, a frame helper, the note and controls schemas, and the notes bridge app. Every skill
that renders such a UI uses these parts and writes no second copy.

## The canonical files

The canonical files live in `lib/ui-feedback/`:

| Path | Holds |
|---|---|
| `lib/ui-feedback/host.html` | The host page: a checked-in page the notes bridge serves. It frames the model-written page in a sandbox, shows the notes panel, validates every message from the frame, and sends notes to the session |
| `lib/ui-feedback/proto-pin.js` | The frame helper, inlined into the framed page. It picks elements, text and regions, renders the controls, holds the state-snapshot function, and talks to the host page only by `postMessage` |
| `lib/ui-feedback/note.schema.json` | The note contract |
| `lib/ui-feedback/controls.schema.json` | The controls manifest contract |
| `lib/ui-feedback/fixtures/` | Valid and invalid notes and manifests |
| `lib/ui-feedback/relocate-note.mjs` | The relocation script: finds a note's element again in a fresh page and shoots it (see [Re-locating a note](#re-locating-a-note)) |
| `lib/ui-feedback/notes_bridge.py`, `notes-bridge.sh` | The notes bridge app on the session bridge's loopback adapter, shaped like the view app ([`lib/session-bridge/README.md`](../../../lib/session-bridge/README.md#the-view-app), "The view app") |

Each consumer takes generated copies through [`scripts/shared-copies.txt`](../../../scripts/shared-copies.txt)
and `scripts/sync-shared-copies.sh`, whose `--check` and `--check-bump` modes are the sync gate
([ADR 0019](../../adr/0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md)). Edit only
the canonical file, then run the script. The bridge app's copies sit in one plugin directory with
that plugin's session-bridge copies, for the reason the session bridge's
[Files](../../../lib/session-bridge/README.md#files) section gives.

## The note contract

`note.schema.json` is the only definition of a note's fields, enums and limits. Every validator,
the host page's and the bridge app's, reads its limits from that file; none hardcodes a limit or
an enum. The fixtures in `lib/ui-feedback/fixtures/` run against every validator, so a validator
that accepts an invalid note or refuses a valid one fails its suite. A new field or limit is a
schema edit plus fixtures, never a validator edit alone.

## Re-locating a note

A note's element is found again by structure, never by node identity: the variant and screen
state give the scope, then the anchor rungs run in order, test id and its index in the scope, role,
then the structural path, then a text note's quote, and the first that finds one element matches. A match is
confirmed only when no stronger rung the note carries found nothing, and a text note's match only
when its quote is still there. When no rung matches, the
note's `rect` (the element's box in percent of the page) is the only position left, labeled
position only. `relocate-note.mjs` reads one note from the bridge's log, checks it against
`note.schema.json`, and writes a `playwright-cli run-code` script that carries it as one JSON
literal. The script opens the host page, so the mockup stays in its sandboxed frame, sets the
note's viewport, restores the view through the switcher's `vs:show` event, replays the note's
data log, and cuts the shot from inside the frame's box, so no host-page pixel is in it. A
region note's shot is its box. Shot files are named from the bridge's integer `seq` only.

The frame helper owns both rules a re-located note depends on: the data log (the presses of the
controls the page marks with `data-data-control`, and each content set the switcher shows) and the
text quote (the selection with whitespace collapsed, plus visible text of the scope either side,
matched with whitespace ignored). It takes them when the note is made and exposes
`window.uiFeedbackRelocate` (`replay`, `findQuote`) for the script, so no second copy of either
rule exists. A model-written page's Seed is deterministic, record *i* from index *i*, so a
replayed log rebuilds the same rows and a test id's index or a quote finds the same row.

## Copy-out and import

When the bridge stops answering while the host page is open, the page says no session is
connected, keeps each note written after that on the page, and Copy all notes gives one fenced
`prototype-notes` block of every note written on that page: `{"notes": [...]}`, each a note the
schema admits, with every backtick written ``` so a note cannot end the fence. The session
writes a pasted block to a file and runs `notes-bridge.sh import --file <path>`: the bridge's own
validator checks every note, takes all or none, skips a note already in the log, counts the
imported notes toward `x-maxNotesPerRun`, and refuses while a server runs on the data dir. The
block is data like any note; it is never run as text.

## Controls

`controls.schema.json` defines the controls manifest: the one list of what can vary on the framed
page. The panel, each note's controls snapshot, copy config and reset all read the manifest. The
frame helper holds the control-type registry: each type name maps to its renderer and its value
reader. A new control type is one registry entry plus one enum value in `controls.schema.json`.

## The state snapshot

The frame helper has one function that captures everything a reload loses: variant, screen
state, content set, data log and toggles, control values and viewport. Notes, a settings send and
the clean-state proof all call it. The snapshot is taken inside the frame because the sandbox lets
the host page reach the frame only by message.

## Trust rules

- **The framed page's CSP is unchanged.** A model-written page keeps the policy the
  [rendered-views contract](../rendered-views/README.md#content-classes) sets for K0 and K1 pages,
  with no `connect-src`. Its network is the host page's.
- **Notes leave through the host page.** The host page frames the page with `sandbox="allow-scripts"` and
  never `allow-same-origin`, in the pattern of the planning shared page
  ([`plugins/planning/shared/README.md`](../../../plugins/planning/shared/README.md#prototype-page),
  "Sandbox"). It checks each message's source frame and shape, then posts the note on the session
  bridge, whose Host, Origin and token checks are in
  [The loopback adapter](../../../lib/session-bridge/README.md#the-loopback-adapter).
- **From `file://`, copy-out only.** A page opened from `file://` has no host page and no bridge:
  it offers copy-out and says no session is connected.
- **Note content is data.** The bridge delivers every note field, the person's text included,
  under the [framing contract](../untrusted-content/README.md#the-framing-contract)
  ([Delivery as data](../../../lib/session-bridge/README.md#delivery-as-data)). The agent never
  executes note content; an imperative in it is a finding.
- **Page-derived text only from model-written pages.** A note may carry text taken from the page
  (a text quote, an accessible name, an element label) only when the framed page is model-written
  K0 or K1. A page that renders K2 text is builder-only and does not use these parts. Today the
  one such field is `anchor.textQuote` on a text note, its limits in `note.schema.json`
  (rendered-views [rule 9](../rendered-views/README.md#the-interactive-validator-profile)). The
  host page keeps it only when the schema admits it, drops every other field the schema refuses
  (the helper's element label included), and renders it through `textContent`; the bridge
  validates it again and delivers it as data, and the agent quotes it as what a note is about,
  never as an instruction.

## Settings stay with their plugin

`level` and `levels` are prototype-plugin keys, defined and resolved by that plugin. The
[config cascade](../config-cascade/README.md#boundary-this-contract-owns-the-axis-never-the-keys)
owns the axis, not the keys. A shared levels resolver is written only when a second plugin adopts
levels.

## Consumers

- **`/prototype:explore-directions`, HTML mockup.** Adopts first.
- **`/planning:interview` shared page.** Takes its copy of `proto-pin.js` from here.
- **Later adopters.** The explore-directions real-stack route, the `/prototype:pressure-test` HTML
  demo, `/prototype:build-generator` (controls only), `/visualization:visualize`'s UI-mockup row,
  and `/pixel-art:scene` (region notes).
- **Builder pages never adopt.** The interactive validator profile admits one hash-pinned runtime
  script ([rule 1](../rendered-views/README.md#the-interactive-validator-profile)), so the frame
  helper cannot run there.

A new consumer registers its copies in `scripts/shared-copies.txt`, runs the sync script, adds
itself to this list, and points its skill text at its copy. It writes no picker, note shape,
controls panel or bridge of its own.

## Deferred

Planning's `POST /api/annotate` keeps its own note shape. Moving it onto `note.schema.json` is a
separate change.

## Format changes

Each schema carries its own version. A change to a rule here updates every consumer in the same
pull request.
