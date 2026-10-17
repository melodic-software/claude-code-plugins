# Shared interview session

The runtime behind the interview skill's shared lane (`skills/interview/context/lane-shared.md`):
one person, the owner, runs a multi-person interview from their own machine. Guests open a
Cloudflare quick-tunnel link; the owner's Claude session drives the session through `share.sh`
and the session-bridge watcher. Python 3 standard library only.

## Files

| File | Job |
|---|---|
| `share.sh` | Launcher: runs `share.py` with the first Python 3 that runs. The session-bridge `CONTROL` script and the only file the skill calls |
| `share.py` | The CLI: `ensure-running`, `stop`, `restart`, `status`, `url`, `list`, `apply`, `lease` |
| `server.py` | One process, two 127.0.0.1 listeners: the guest listener (the page and `/api/*`) and the control listener (session-bridge). Routes, auth, caps, headers and the snapshot; no domain rules |
| `session.py` | The domain rules over `state.json` (people, rounds, questions, votes, locks, proposals, requests, results, digest, ops) |
| `migrate.py` | `schemaVersion` migrations, `(dict, ctx) -> dict`, including `0 -> 1` from the prototype's state file |
| `tunnel.py` | cloudflared: start, address parse, reattach, adopt, exit detection, stop. The only file that names cloudflared |
| `detached.py` | Processes that outlive their starter, and liveness and stop by pid, on Windows, macOS and Linux |
| `session_bridge.py`, `watch.sh`, `wake.sh` | Generated copies of `lib/session-bridge/` (`scripts/sync-shared-copies.sh`); edit the canonical, never these |
| `session-bridge.conf` | `NAME=shared`, `CONTROL=share.sh` |
| `schema/*.schema.json` | The persisted and wire shapes: `state`, `ops`, `event`, `question-shape`, and `wire` (the heartbeat body and a presence entry, kept only in memory) |
| `web/` | The page, served from a fixed allowlist (`/`, `/core.js`, `/app.js`, `/core.css`, `/app.css`, `/proto.js`), plus `/proto/<qid>` (`proto.html`) for a prototype question; `proto-pin.js` is served only inside an html variant (see [Prototype page](#prototype-page)). `core.js` is the only code that talks to the server: it polls `/api/state?since=<rev>`, reloads the page when `schemaVersion` or the build changes, builds the state `app.js` reads, and words errors by their code. The guest secret stays under the prototype's `localStorage` key, `secret`. `web/harness.html` is test-only and off the allowlist: `ui_inputs.js` serves it into the page's origin from the browser |
| `tests/` | `test_session.py`, `test_server.py`, `test_share.py`, `test_tunnel.py`, `test_load.py`, `test_migrate.py`, `test_schema_shapes.py`, `tracer.test.sh`, `tracer-live.test.sh`, `ui_journey.js`, `ui_formats.js`, `ui_presence.js`, `ui_layout.js`, `ui_keyboard.js`, `ui_inputs.js` (with `harness-open.js`), `ui_chat.js`, `ui_proto.js`, `align.test.sh` (with `align.js`), `browser_harness.js`, and `fixtures/` (incl. `fake-cloudflared.sh` and `fake_cloudflared.py`) |

## Run

```bash
bash '<plugin-root>/shared/share.sh' --dir '<data_dir>' ensure-running --open --defaults-file '<data_dir>/defaults.json'
```

Every command prints one JSON line on stdout and diagnostics on stderr. On Windows,
`python share.py --dir <data_dir> ...` runs without bash.

| Command | Args | Output |
|---|---|---|
| `ensure-running` | `[--open] [--defaults-file F] [--guest-port N] [--import STATE] [--adopt-tunnel PID URL]` | `{ok, guestUrl, localUrl, ownerLinkFile, shareChanged, resumed, tunnel, watch}`: starts or reuses the server and the tunnel. A new session's `state.json` comes from `defaults.json` (`{"settings": {...}}`, state.schema field names). `--guest-port` applies only when the session is created; later starts reuse the recorded ports. `--import` and `--adopt-tunnel`: see [Moving the prototype's session](#moving-the-prototypes-session) |
| `stop` | `[--keep-tunnel]` | `{ok, stopped}`: ends the armed watcher, the server and cloudflared (an adopted cloudflared keeps running; see [Moving the prototype's session](#moving-the-prototypes-session)); keeps the ports and the state. `--keep-tunnel` keeps the guest link for the next start |
| `restart` | | Stops and starts the server only, on the same ports, with the same control token: the tunnel, the guest link, the state and an armed watcher all survive. Open pages see the new build and reload |
| `status` | | `{ok, running, tunnel, guestUrl, round, intro, people, queue, unhandled, lease}`; `intro` is true once "Why you're here" is set |
| `url` | `[--owner]` | `{guestUrl}`, or `{ownerUrl}` (a credential, printed only on request) |
| `list` | `--root '<memory_dir>'` (no `--dir`) | `{sessions: [{dir, title, running, guestUrl, round, ended}]}` |
| `apply` | `--file F` | `{ok, results}`; deletes `F` once it applies. A missing `F` is a no-op, so `wake.sh` re-arms with nothing to write |
| `lease` | `[--release]` | `{lease}` |

Exit codes: 0 done; 1 refused (bad arguments, a state file from a newer version, a failed
migration, a `--guest-port`, `--import` or `--adopt-tunnel` on an existing session, an adopted pid
that is not a running cloudflared to the guest port); 2 a prerequisite is missing (Python 3, curl,
cloudflared) or the server cannot start or be reached, a busy `--guest-port` included; 3 no tunnel
address in time (the server keeps running on `localUrl`, `tunnel: "down"`).

The tunnel is its own detached process and outlives server restarts. The server checks it every
second: when cloudflared exits, the server starts a new one (backing off up to a minute while it
fails), allows the new host, and records the new link in `session.share` with `changedAt`, which
the owner's view shows as "New guest link, share again"; the next `ensure-running` says
`shareChanged: true`. `python tunnel.py adopt --dir D --pid N --url U --port P` records a
cloudflared that is already running, without starting anything; it is then watched and restarted
like one the server started.

## Moving the prototype's session

`ensure-running` needs cloudflared on PATH even with `--adopt-tunnel`: it exits 2 without one, and
by then the prototype is already stopped. Check first, then stop the prototype (leaving its
cloudflared running), then import:

```bash
command -v cloudflared || { echo "cloudflared is not on PATH: fix PATH before stopping the prototype"; exit 1; }
bash '<plugin-root>/shared/share.sh' --dir '<data_dir>' ensure-running \
  --import '<prototype>/state-<port>.json' --guest-port <port> --adopt-tunnel <cloudflared pid> <tunnel URL>
```

Creates the session from the prototype's state file and refuses (exit 1) when `<data_dir>` holds
one already. The flags may instead be `defaults.json` keys, `import`, `guestPort` and
`adoptTunnel: {pid, url}`, which apply only when the session is created.

- **State.** `migrate.py` maps the prototype's file (no `schemaVersion`) to version 1: people keep
  their pid and name, guest secrets are stored as sha256 (a browser's secret still names the same
  person), the owner token as its hash; questions, options, answers, picks, votes, Claude's cards,
  locks, suggestions, chat, ideas (as proposals), requests, research (as published results),
  merge requests, prefs, notifications, settings, title, goal, guest key and share URL carry over.
  Each field with no counterpart, link that is not http(s), or asset name that is not an image
  file name is dropped and named in `server.log`, never its value; records naming no known
  question or person are counted per collection. A guest secret the prototype mapped to the host
  (a join with the owner token, or a guest merged into the host) is dropped: only the owner link
  carries owner identity, so that browser joins again. Uploads do not carry over yet. A round the
  prototype had sent to Claude opens again. The original stays beside it as `state.v0.json`.
  Once the import works, delete the prototype's own state file or `chmod 600` it: it holds every
  guest secret and the owner token in plain text.
- **Owner link.** The prototype's owner token stays the owner's credential, so its owner link keeps
  working; one shorter than 16 characters, or kept only on the prototype's command line, is
  replaced (`url --owner` prints the new link).
- **Assets.** The images its questions show are copied from the `assets/` folder beside the state
  file.
- **Tunnel.** The running cloudflared is recorded as the session's tunnel and nothing is started,
  so the guest link stays the same; it is then watched like the server's own. `--adopt-tunnel`
  needs `--guest-port`, the port that cloudflared points at, and refuses (exit 1) a pid whose
  program file is not `cloudflared` (`cloudflared.exe` on Windows) or whose one `--url` is not
  `http://127.0.0.1:<port>` or `http://localhost:<port>`, or cannot be read. The session never
  signals an adopted cloudflared: `share.sh stop` drops its record and leaves it running, so the
  prototype can take the same link back; end it yourself (`kill <pid>`, or `Stop-Process -Id <pid>`
  on Windows) to close the link. If it exits, the server starts a cloudflared of its own (a new
  link), which `stop` ends like any other.
- **Open prototype pages.** In an imported session a poll of `GET /api/state` that carries an
  identity header and no query string is a prototype page still open from before: it gets
  `{schemaVersion, rev, outdated: true, title: "This page was updated: reload"}`, which the old
  script shows as its title over an empty page. The plugin's page polls with `?since=<rev>`.

## Ops

`share.sh apply --file <data_dir>/ops.json` takes `{"ops": [...]}`, checked against
`schema/ops.schema.json` before any applies; all land or none does (`{error, op, message}` names
the refused op's index).

| Op | Fields | Effect |
|---|---|---|
| `set-title`, `set-goal` | `title` / `goal` | |
| `set-intro` | `intro` (0..600) | "Why you're here", shown to a guest before question 1; empty removes it |
| `open-round` | `questions` (1..8), `placements?` | Closes the `working` round (or starts round 1) and opens the next |
| `close-round` | `placements?`, `reason?` | `working` -> `closed`, no new round |
| `ack-round` | `round` | `sent` -> `working` |
| `result` | `qid`, `request?`, `kind`, `used`, `why`, `summary`, `sources`, `report` | Stores a result unpublished; the owner publishes or discards it |
| `fail-request` | `request`, `reason` | `running` -> `failed` |
| `add-reference`, `remove-reference` | `qid`, `reference` / `index` | |
| `add-asset` | `path`, `as?`, `scale?` | Copies a PNG, JPEG, WebP, SVG or HTML file (by its bytes, at most 10 MB) from the data folder, where captures go in `staging/`, into `assets/<16 hex>.<ext>`, named by its content; returns `{id, kind, bytes, at, scale}`. Usable from the next apply; a refused apply removes the files it copied and puts back any sidecar it rewrote |
| `make-question-from` | `proposal`, `question` | |
| `handle` | `seqs` | Marks events handled |

## Answering

How people answer each `format` through `POST /api/pick` (`{qid, view, device?, comment?, ...}`):

| Format | Pick field | Rule |
|---|---|---|
| `choice`, `confirm`, `prototype` | `option` (`""` for none) | One pick, which is the person's vote |
| `multi` | `options` (`[]` for none) | A subset of the option ids, each at most once |
| `scale` | `value` (`null` for none) | A whole number from `min` (1) to `max` (3..10) |
| `rank` | `order` (`[]` for none) | Every option id once |

- **Something else.** The server adds one `{id: "other", other: true}` option to every `choice`,
  `multi` and `rank` question and refuses one in Claude's ops. Picking it needs `other`, the
  person's own option, which becomes their card's text. Others back that card with
  `POST /api/vote {qid, card, on}`: on a `choice` question that moves their one pick to it; on
  `rank` it is one vote, outside the Borda count; on `multi` a person backs any number of them,
  kept in `backs` (`{qid: {pid: [ref]}}`), outside the picks. `scale` and `confirm` take a
  `comment` instead.
- **Disagree.** `POST /api/disagree {qid, card, reason}` on a `decide` question records a reason
  (1..200 characters), one per person per answer; `on: false` takes it back. Vote counts never
  change, and the digest lists each one under its question.
- **Reactions.** `thumbs`, `down`, `heart` and `idea`, on `gather` questions only.
- **Digest.** `multi` reports picks per option; `scale` the count per value, the mean (two places)
  and the median; `rank` Borda totals (with n options a first place scores n-1, a last 0) and how
  many gave each full order. Each lists people's own options with their backers, and the comments.
- **Presence.** The heartbeat (`schema/wire.schema.json`) carries `visible`, `lastInput` (seconds
  since the last key, pointer or touch) and `away` (the person's own snooze, sent until their next
  input), and `tab`, an id each browser tab keeps for its life (in `sessionStorage`). The server
  keeps a beat per tab, at most 8 per person, the least recent dropped. A tab is live until 90 s
  without a beat; a person with no live tab is offline. A tab is Away while hidden, after 5 minutes
  visible with no input, or snoozed; the person is Active while any live tab is Active, and Away,
  `since` the last tab went Away, only when every live tab is. Their question and typing come
  from their latest beat, and typing flags last 5 s. Each tab's beats have their own one-a-second
  limit, and a beat that changes `visible` or `away` is taken at once. The page beats every 2 s
  and at once on a visibility change, never two from one tab within the limit, and sends its own
  writes to one route a second apart. The write limits count per person, not per tab, so one
  person writing the same route from two tabs or devices within a second gets a 429 on the second
  write, which the page shows as an error to send again. A duplicated tab copies `sessionStorage`,
  so it beats under the original's id and the two share one limit.

## Moderation

Owner-only routes (`X-Owner-Token`); a leader cannot use them.

| Route | Body | Effect |
|---|---|---|
| `/api/card/hide` | `{qid, card, on, reason?}` | A hidden answer leaves every other person's snapshot, the tally (its picks too) and the digest, and its text leaves the mention notifications it sent; its author still gets it with `hidden {by, at, reason?}`. It stays hidden through its author's new versions until `on: false` shows it. Refused (409 `locked`) on the locked answer: unlock first |
| `/api/card/edit` | `{qid, card, text}` | Replaces the text and sets `edited {by, at}`, which everyone sees and the digest marks; an edit after votes sets `editedAfterVotes`, an edited own option loses its backers, and the text leaves the mention notifications it sent. Locking an edited answer stores `editedBy: "host"` on the lock and the digest marks it `edited` |
| `GET /api/card/history?qid=&card=` | | Once the owner has hidden or edited an answer, every replaced version goes to its `history` (the original kept, then the newest, 50 in all); before that its author's edits keep none. This route returns one answer's `history`; the owner's snapshot carries only `versions`, the count. An answer its author clears after the owner hid or edited it leaves a tombstone in `cleared` (in the owner's snapshot as `{ref, pid, clearedAt, hidden}`); this route returns its last `text` with `cleared: true`, and the author's next answer there takes it up, hidden if it was |
| `/api/join/act` | `{pid, action: admit\|decline}` | With the `approveJoins` setting on, a join gets a secret but waits (`status: waiting`, 403 `waiting` on every route) in the owner's `joinRequests` (in join order `n`, with the `device` and `browser` the join named) until admitted; declining removes the person. At most 20 wait (503 `waiting-full`), and a full session never evicts a waiting person. People whose secret already resolves are not affected |
| `/api/session/intro` | `{intro}` | Edits "Why you're here" |

`POST /api/chat/react {id, emoji, on}` (any person) adds or takes back one's own emoji on a chat
message: only the page's fixed set (`CHAT_EMOJI` in `session.py` and `web/app.js`), at most 20
distinct per message and 6 per person per message, one reaction a second per person per message.
Chat and its reactions stay out of the digest; a reaction tells the message's author in one
rolled-up notification.

There is no device or address blocking (C35): Remove stops a person's secret, and Approve new joins
or a new guest link stops a removed person rejoining under a new name.

## Prototype page

A `prototype` question shows a preview tile and an "Open prototype" link to `GET /proto/<qid>`
(`web/proto.html`, `proto.js`; 404 for any other question). The page switches between the
variants, picks one, and with Annotate on pins a note to a part of a variant:
`POST /api/annotate {qid, variant, anchor: {selector, rect}, text}` (any person, once the
question's round has opened; 30 notes per person per question; 2000 in the session, after which a
new note gets 409 `notes-full` and none is dropped). Notes show on the page, in the question's
Claude thread, and in the round's digest as `{qid, variant, text, element}`; `element` is `null`
for a free-form selector an earlier build took.

- **Anchor.** `selector` is the element's path from the variant's root, such as
  `html > body:nth-of-type(1) > main:nth-of-type(1)` (tag names only, each below the root with
  `:nth-of-type(n)`, at most 32 levels and 1000 characters), or
  `img` on a picture variant; anything else is refused (400 `bad-field`, `anchor.selector`).
  `rect` is the element's box in percent of the variant's reference box: an html variant's whole
  scrollable page when the note was pinned, a picture variant's image. It places the pin when the
  path no longer finds the element.
- **Sandbox.** An html variant is framed from `/assets/<id>.html?pin=1` with `sandbox="allow-scripts"`
  and the asset's own CSP sandbox, never `allow-same-origin`, so it reaches no cookie, storage or
  session route. `?pin=1` appends `web/proto-pin.js` as an inline script; it answers the page by
  `postMessage` with an element's path, box and up to 60 characters of its label, and
  `proto.js` checks every message (its source frame, the selector and the rect) before use, and
  takes the first `ready` only. A variant that navigates its own frame (a second `load`) is
  dropped: the page stops posting to it, ignores it, and says it tried to leave its page. The
  page's `frame-src 'self'` already refuses a page from another site in the frame.
  `server.py` refuses to start when the helper holds `</script`, `<script` or `<!--`.
- **Owner token.** Links to session pages (`Core.pageLink`) never hold it. The page keeps it in
  the tab's `sessionStorage`, takes it out of the address bar, and uses it again only on a reload
  or Back in that tab; when the owner follows a session link, `core.js` opens the page with
  `#owner=` in its fragment (a new tab with `noopener`), and that page takes it out in turn.

## Data contract

One folder per session: `<memory_dir>/<topic-slug>/shared/<session-slug>/`.

| Path | Writer | Mode | Holds |
|---|---|---|---|
| `state.json`, `state.v<N>.json` | server | 0600 | The session (`schema/state.schema.json`); the pre-migration copy. `state.v0.json`, the prototype's file, holds its guest secrets and owner token in plain text |
| `defaults.json` | the skill | | Settings for a new session; `import`, `guestPort`, `adoptTunnel` for an imported one |
| `ops.json` | Claude | | One apply; deleted when it lands |
| `.shared-secrets.json` | server (made on first start) | 0600 | The control token, the owner token and `ownerAt`, when the owner token was issued |
| `.owner-link` | server | 0600 | `http://127.0.0.1:<guest port>/#owner=<token>` |
| `.owner-open-<hex>.html` | `share.py ensure-running --open` | 0600 | A page that sends the browser to the owner link; deleted 30 s later |
| `staging/` | server (made at every start) | 0700 | Captures Claude saves for `add-asset` |
| `.shared-session.json`, `.shared-session.env` | session-bridge `start` | 0600 | Control port, pid, control token, nonce |
| `.shared-ports.json` | server | 0600 | The guest and control ports, reused on every start |
| `.shared-tunnel.json` | `tunnel.py` | 0600 | `{pid, url, port, startedAt, marker, adopted}` |
| `cloudflared.log` | cloudflared | 0600 | Its output, where its address is read |
| `server.log` (+ `.1`..`.3`) | server | 0600 | One line per request (method, path, status, time); rotated at 1 MB, 3 kept |
| `.shared-server.err` | the server's stderr | 0600 | Why a start failed |
| `.shared-reported` | `share.py` | 0600 | The guest link the last `ensure-running` printed (for `shareChanged`) |
| `.watch-seq`, `.watch-replay` | `watch.sh` | | |
| `assets/<16 hex>.<ext>`, `assets/.<id>.json` | server (`add-asset`) | | The file, and its kind, size and scale |

Every `GET /api/state` with identity carries `schemaVersion`, `rev` and `build` (a hash of the
served web files); every answer carries `X-Shared-Build`. A page built for another version or
build reloads itself.

## Security model

- **Two listeners, both 127.0.0.1.** Only the guest listener is the tunnel's target. The control
  listener (ops, the watcher's long-poll, status) is never tunneled and needs `X-Shared-Token`.
- **Host and Origin.** The guest listener serves `Host` `127.0.0.1:<port>`, `localhost:<port>` and
  the current tunnel host only (DNS rebinding), and checks `Origin` when sent. A changed tunnel
  drops the old host.
- **Identity is a header.** `X-Session-Secret` (a guest) or `X-Owner-Token` (the owner), never a
  body field or a URL query; a pid in a body is ignored. Owner routes need `X-Owner-Token`
  itself. `state.json` keeps only sha256 hashes. Custom headers force a CORS preflight that is
  never answered.
- **Requests.** JSON POSTs only (415), the 32 KB body cap checked before reading (413), and the
  whole body within 10 s (408). A request other than a POST that carries a body
  (`Content-Length` above 0 or any `Transfer-Encoding`) gets 400 and its connection closes. A
  refused request (bad host, rate limit, body) answers once and runs nothing.
- **Limits.** All are constants at the top of `session.py`:

  | Limit | Value |
  |---|---|
  | Requests per address (`CF-Connecting-IP` only, never `X-Forwarded-For`; an IPv6 address counts by its /64) | 100 a second, bursts of 200; the 10000 most recently seen addresses are remembered |
  | Joins | 30 a minute per address and guest key; 60 per 10 minutes per guest key across all addresses (rotating the guest link starts a new count) |
  | Writes | 1 a second per person per route, on every route that writes (answer, pick, vote, react, disagree, go-with, rename, color, prefs, about-you, notifications/read, chat, propose, suggest, request, annotate, merge-request) |
  | Heartbeat | 1 a second per person and tab (429 otherwise), except a beat that changes `visible` or `away` |
  | Stored chat, notes, suggestions | the newest 2000 messages; 2000 notes, then a new one is refused (409 `notes-full`); 200 suggestions per question, with votes on a dropped one dropped too |
  | Connections served at once | 64; one more is answered 503 `busy` |

- **Headers.** Every answer, http.server's own refusals (414, 501 and the like) included:
  `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy: no-referrer`. HTML adds the page policy (`default-src 'self'` ...
  `frame-ancestors 'none'; base-uri 'none'; form-action 'none'`). `/assets/*` adds
  `Content-Disposition: inline` and `Content-Security-Policy: sandbox`; an HTML asset gets
  `sandbox allow-scripts; default-src 'none'; script-src 'unsafe-inline'; style-src
  'unsafe-inline'; img-src 'self' data:; font-src data:; connect-src 'none'; frame-ancestors
  'self'`, never `allow-same-origin`, and `X-Frame-Options: SAMEORIGIN` in place of `DENY`, so the
  prototype page can frame it and no other site can.
- **The log.** `server.log` writes the request path, and a failure's traceback on one line, with
  control characters escaped (`\x1b`, `\x0a`).
- **What a visitor reads.** Without identity, `/api/state` is `{title, ended, joinNeedsKey,
  schemaVersion}` only; a removed person and an owner link from before a rotation read nothing.
  Results stay hidden from guests until the owner publishes them.
- **Guest text is data.** Answers, chat, proposals and requests reach Claude in the digest,
  delivered with session-bridge's data note; an instruction in them is a finding, never a request.
- **Files.** `add-asset` reads only regular files under the data folder with no hidden folder or
  name below it, and only when the bytes are an allowed type. Claude saves captures in
  `<data_dir>/staging/` (0700); the system temp folder is refused.
- **Name hiding.** When the session shows initials or "someone", a join never answers `was` (the
  earlier person with the same name), so a join cannot probe for hidden names.
- **Owner-link rotation.** The new token reaches `.shared-secrets.json` before its hash reaches
  `state.json`, both under the session lock. A start whose secrets file holds a token issued before
  the session's last rotation refuses (exit 1) rather than bring the retired link back; deleting
  `.shared-secrets.json` issues a new owner link. A secrets file without `ownerAt` whose owner
  token is not the current one gets a fresh owner link, and a rotation time ahead of the clock is
  set to the start time; `server.log` records both. After such a clock rollback, a token whose
  issue time is recorded but which is not the current one gets a fresh owner link as well.

Where each token can be seen:

| Token | Exposure paths |
|---|---|
| Owner token | `.shared-secrets.json` and `.owner-link` (0600); for an imported session, `state.v0.json` (0600) and the prototype's own state file; for 30 s after `--open`, the `.owner-open-<hex>.html` page (0600) the browser is handed, whose path, not the token, is on the opener's command line; the owner's browser (the link's fragment, never sent to the server, and its history; the tab's `sessionStorage` once a page took it out of the address bar); the transcript when the owner asks for `url --owner` |
| Guest secret | The guest's browser storage and personal link (`#me=` fragment); for an imported session, `state.v0.json` (0600); the `X-Session-Secret` header, which Cloudflare's edge sees because the tunnel terminates TLS there |
| Control token | `.shared-secrets.json`, `.shared-session.json`, `.shared-session.env` (0600); the `curl` command line `watch.sh` runs (the generated session-bridge watcher puts the header on argv). A command line is readable by other local users on Linux without `hidepid` and on macOS, not only by the same user; moving that token off argv is tracked in #7693 |

Neither token is on the server's command line: the server reads both from the secrets file.
`stop` drops the control token, so the next start makes a new one; `restart` keeps it.

## Supported platforms

Windows, macOS and Linux. Process start, liveness and stop go through `detached.py`: POSIX gets
`start_new_session`, TERM and a zombie-aware pid check; Windows gets `DETACHED_PROCESS |
CREATE_NEW_PROCESS_GROUP` (breaking away from the caller's job when allowed), `OpenProcess` and
`GetExitCodeProcess`, and the guest port is bound with `SO_EXCLUSIVEADDRUSE`. A recorded pid
counts only while its command line (POSIX) or executable (Windows) names the expected program, so
a pid the OS reused is never stopped. Detached children start in the data folder.

File modes are 0600 where the OS has them. Windows has none here, so `ensure-running` and the
server refuse (exit 1) a data folder outside `%USERPROFILE%`, whose inherited access limits it to
the user, administrators and SYSTEM; the runtime sets no access list of its own. On WSL they refuse a data folder on a DrvFs mount (`/mnt/<drive>`)
unless it is mounted with `metadata`, since without it every file there is readable by all. On
Windows cloudflared is looked up with `NoDefaultCurrentDirectoryInExePath=1`, and a match in the
current folder is refused, so a `cloudflared.exe` planted there never runs. `share.sh` runs under
Git Bash; `share.py` runs directly. cloudflared install hints are in
`plugins/planning/prerequisites.json`.

## Load

`tests/test_load.py`: 20 people each write an answer once a second while their pages poll
`/api/state` every 1.5 s. On the development machine (WSL2, Python 3.14, 30 s run, 572 writes):
p50 1.2 ms, p95 1.6 ms. The test fails above a 1 s p95.

## Tests

```bash
python3 -m unittest discover -s plugins/planning/shared/tests
bash plugins/planning/shared/tests/tracer.test.sh
bash plugins/planning/shared/tests/tracer-live.test.sh [CLOUDFLARED]
node plugins/planning/shared/tests/ui_journey.js
node plugins/planning/shared/tests/ui_formats.js
node plugins/planning/shared/tests/ui_presence.js
node plugins/planning/shared/tests/ui_layout.js
node plugins/planning/shared/tests/ui_keyboard.js
node plugins/planning/shared/tests/ui_inputs.js
node plugins/planning/shared/tests/ui_chat.js
node plugins/planning/shared/tests/ui_moderation.js
node plugins/planning/shared/tests/ui_acceptance.js
node plugins/planning/shared/tests/ui_proto.js
bash plugins/planning/shared/tests/align.test.sh
```

`ui_proto.js` checks the prototype page on a desktop and a 390x844 phone in separate browser
contexts: the preview tile and its link, the variant switcher, Annotate, a note pinned to an
element of an html variant and to a spot of a picture, the notes in the Claude thread and the
digest, the variant's sandbox, and a forged pin message being ignored.

`ui_layout.js` checks no page scroll at five sizes and 200% zoom in both themes, 44 px phone
targets, the answer box right under the question, a guest's first view (goal, the host's ask,
"Start here: question 1"), the ten person colors against WCAG 2.2 AA, and the phone edit sheet.
`ui_keyboard.js` checks focus traps, Escape, focus return, announcements and the first-visit tour
(the `tour` pref). `ui_inputs.js` types 2000 characters and pastes a 300-character word into each
input surface on iPhone and Pixel profiles at keyboard-open heights and on a desktop. `ui_chat.js`
checks the host's unread badge, a frozen tab catching up, and the new-messages pill.
`ui_moderation.js` checks the intro before question 1 and from the header, a phone's first screen
with the intro folded, Hide and Edit with the owner-only history, chat reactions, the owner's
per-person view, and Approve new joins. `ui_acceptance.js` checks the Brief acceptance criteria no other
suite drives in a browser: the join note and a refused join, Claude's take, the round states and toasts, Follow,
Reconnecting, the new guest link, the ended session, the Host view per role, the phone header and height, and
the views sharing data.
`align.test.sh` (about 3 minutes) is the C41 pixel pass over 47 views; `ALIGN_VIEWS` and
`ALIGN_SIZES` narrow it.

`ui_journey.js` drives the page in Chromium against `ensure-running` on spare ports with the fake
tunnel: the owner and a guest join, answer, vote, lock, pick, react and send a round; every state
poll carries a query string; no page breaks the CSP; and a guest of an imported prototype session
comes back as the same person, keeping its stored secret when its first heartbeats get a 429 or
no answer. `ui_formats.js` covers, in a session past its first round, `multi`, `scale` and `rank`
(keyboard, and touch on a 390x844 phone, whose Questions tab must take taps with two rounds
listed), Something else on `choice`, `multi` and `rank`, Disagree, the `down` reaction and a
diagram's alt text. `ui_presence.js` (about 4 minutes) hides a tab for 3 minutes with throttled
timers, closes another, snoozes a third, keeps one person in two tabs with one hidden, and checks
none of that gets a 429. The
browser suites share `browser_harness.js` (not a test), need playwright-core (from `node_modules`,
or the one playwright-cli bundles), and SKIP without it. `tracer.test.sh` runs the whole flow against the fake tunnel. `tracer-live.test.sh` uses a real
cloudflared (a path argument, else PATH), opens a public address, and SKIPs in CI or without one.
