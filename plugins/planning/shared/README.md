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
| `session.py` | The domain rules over `state.json` (people, rounds, questions, votes, locks, proposals, requests, results, uploads, digest, ops) |
| `migrate.py` | `schemaVersion` migrations, `(dict, ctx) -> dict`, including `0 -> 1` from the prototype's state file |
| `tunnel.py` | cloudflared: start, address parse, reattach, adopt, exit detection, stop. The only file that names cloudflared |
| `detached.py` | Processes that outlive their starter, and liveness and stop by pid, on Windows, macOS and Linux |
| `session_bridge.py`, `watch.sh`, `wake.sh` | Generated copies of `lib/session-bridge/` (`scripts/sync-shared-copies.sh`); edit the canonical, never these |
| `session-bridge.conf` | `NAME=shared`, `CONTROL=share.sh` |
| `schema/*.schema.json` | The persisted and wire shapes: `state`, `ops`, `event`, `question-shape`, and `wire` (the heartbeat body and a presence entry, kept only in memory) |
| `web/` | The page, served from a fixed allowlist (`/`, `/core.js`, `/app.js`, `/connect.js`, `/core.css`, `/app.css`, `/proto.js`, `/web-vitals.attribution.iife.js`), plus `/proto/<qid>` (`proto.html`) for a prototype question; `proto-pin.js` is served only inside an html variant (see [Prototype page](#prototype-page)). `core.js` is the only code that talks to the server: it polls `/api/state?since=<rev>`, reloads the page when `schemaVersion` or the build changes, builds the state `app.js` reads, and words errors by their code. The guest secret stays under the prototype's `localStorage` key, `secret`. `web-vitals.attribution.iife.js` is the web-vitals 6.2.3 attribution build, copied unedited from its npm package, with that package's Apache-2.0 license beside it as `web-vitals.LICENSE` (not served). `web/harness.html` is test-only and off the allowlist: `ui_inputs.js` serves it into the page's origin from the browser |
| `tests/` | `test_session.py`, `test_server.py`, `test_share.py`, `test_tunnel.py`, `test_load.py`, `test_migrate.py`, `test_schema_shapes.py`, `tracer.test.sh`, `tracer-live.test.sh`, `ui_journey.js`, `ui_formats.js`, `ui_presence.js`, `ui_layout.js`, `ui_keyboard.js`, `ui_inputs.js` (with `harness-open.js`), `ui_chat.js`, `ui_chat_history.js`, `ui_lists.js`, `ui_proto.js`, `ui_connect.js`, `ui_uploads.js`, `ui_report.js`, `ui_clientlog.js`, `ui_telemetry.js`, `align.test.sh` (with `align.js`), `bench_snapshot.py`, `browser_harness.js`, and `fixtures/` (incl. `fake-cloudflared.sh` and `fake_cloudflared.py`) |

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
| `logs` | `[--errors] [--since MINUTES]` | `{ok, lines}`: the newest 200 lines of `server.log` and its rotated files, oldest first; no server needed. `--errors` keeps refusals, server errors and client entries. See [Logs](#logs) |

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
  carries owner identity, so that browser joins again. (Merging a guest into the owner in a running
  session instead answers that browser 401 `merged-into-owner`; see [Moderation](#moderation).)
  Uploads do not carry over yet. A round the
  prototype had sent to Claude opens again. The original stays beside it as `state.v0.json`.
  Each later step keeps the file it read as `state.v<N>.json`. Version 3 stores mentions as
  `<@pid>` (see Mentions under [Moderation](#moderation)): an "@Name" only one person holds now becomes theirs; then,
  for a chat message with one "@Word" left and one mention notification about it to someone it
  does not name already, Word becomes that person wherever Word names only them. Anything still
  ambiguous keeps its "@Name" text.
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
| `result` | `qid?`, `request?`, `kind`, `used`, `why`, `summary`, `sources`, `report` | Stores a result unpublished; the owner publishes or discards it. No `qid` answers a request about the whole session, which `request` must name (see [General asks](#general-asks)) |
| `fail-request` | `request`, `reason` | `running` -> `failed` |
| `add-reference`, `remove-reference` | `qid`, `reference` / `index` | |
| `add-asset` | `path`, `as?`, `scale?` | Copies a PNG, JPEG, WebP, SVG or HTML file (by its bytes, at most 10 MB) from the data folder, where captures go in `staging/`, into `assets/<16 hex>.<ext>`, named by its content; returns `{id, kind, bytes, at, scale}`. Usable from the next apply; a refused apply removes the files it copied and puts back any sidecar it rewrote |
| `set-purpose` | `qid`, `purpose` | The owner's `/api/question/purpose` rules |
| `set-for` | `qid`, `for` | Who must answer, by name or pid; `[]` asks everyone. The owner's `/api/question/for` takes the same body. A question in `open-round` takes `for` too |
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
- **Reactions.** `thumbs`, `down`, `heart` and `idea`, on `gather` questions only. `POST /api/react
  {qid, card, reaction, on}` turns one on or off; a person holds any number at once, kept as a list
  (`reactions` is `{qid: {card: {pid: [reaction]}}}`), never one twice and never both `thumbs` and
  `down`: turning one of those on turns the other off. `reaction: null` clears all of theirs.
- **Pass.** `POST /api/pass {qid, reason?, on}` on any purpose records that the person gives no
  view (`passes` is `{qid: {pid: {reason?, ts}}}`); `on: false` takes it back, and their own
  answer, pick or vote replaces it. The reason is up to 200 characters, required (400 `empty`,
  `field: reason`) of a person the question is `for`. A pass is no pick, so a poll's results still
  wait for one.
- **Taking part.** One rule, `session._took_part`, mirrored by `Core.tookPart`: an own card, a vote,
  a back, any reaction, a Disagree or a Pass. For a person the question is `for`, only an own card,
  a vote or back, or a Pass counts. A question still asks a person (`_owes`) while they have not
  taken part and it is `for` them or no one else has answered it; once one other person has, it is
  optional for the rest. The Host view's `behind` and the page's counts count `_owes`; the digest's
  `people.answered` counts who took part.
- **Late acts.** A vote, back, reaction, Disagree or Pass on a closed round's question is stamped in
  `lateActs` (`{qid: {pid: {round, at}}}`), and the next digest's `late` lists what that person
  holds there, each with `act`.
- **Digest.** `multi` reports picks per option; `scale` the count per value, the mean (two places)
  and the median; `rank` Borda totals (with n options a first place scores n-1, a last 0) and how
  many gave each full order. Each lists people's own options with their backers, and the comments.
  Every question carries `passed` (`{by?, reason?}`; `by` with `digestNames`, and always for a
  person it is `for`) and `silent` (active guests with no signal); one `for` named people adds
  `for` and `missing`, by name. A `gathered` answer carries `endorsedBy`, the 👍 and ❤️ givers:
  names with `digestNames`, else a count; on a question with options it carries `picked`, the
  label of the option the person chose, and its `text` is their comment, which may be empty.
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
| `/api/person/merge` | `{from, to}` | `from`'s answers, votes, reactions, chat, requests, uploads and problem reports move to `to`, every mention of `from` names `to`, and `from` goes. Into the owner, `from`'s secrets end instead of moving: that browser's next request gets 401 `merged-into-owner` (remembered until the server restarts), and its page asks for the owner link instead of joining again |
| `/api/report/act` | `{id, action: seen\|resolved\|ask}` | Marks a problem report seen or resolved (409 `wrong-status` once resolved, or when it already is); either tells the reporter in a `report` notification. A resolved report leaves the owner's snapshot. `ask` sets `asked` on an open or seen report and writes `report-filed` for Claude (409 `wrong-status` on one that is resolved or already asked) |
| `GET /api/report/image?id=` | | One report's screenshot as `{id, image}`, a data: URL |

`POST /api/chat/react {id, emoji, on}` (any person) adds or takes back one's own emoji on a chat
message: only the page's fixed set (`CHAT_EMOJI` in `session.py` and `web/app.js`), at most 20
distinct per message and 6 per person per message, one reaction a second per person per message.
Chat and its reactions stay out of the digest; a reaction tells the message's author in one
rolled-up notification.

**Chat history.** A snapshot carries the newest 50 messages, with `chatBefore` (the oldest of them)
while older ones exist. `GET /api/chat?before=<id>` (any person) returns the messages just older
than that one, and `?around=<id>` the ones with that one in the middle, `limit` of them (1 to 100,
default 50), each read as the snapshot reads it: from people still in, others' reactions masked
where names are; an answer carries `before` while older ones exist, and a message it cannot show
is 404 `not-found`. While older messages exist, a snapshot also carries `chatTouched`, a count that moves
when one of them gets a reaction or is forwarded (kept in memory only, so it starts again from zero when the
server restarts); a page holding older messages reads them again when it moves. The page keeps every message it has read while it is open, loads older ones as
the reader nears the top of the chat or presses "Load earlier messages", and reads around a
message a notification or a reply quote points at.

**Mentions.** People type "@Name" in chat, answers, comments, suggestions, proposals, notes and
requests; the server stores each name of a person who is in as `<@pid>` (`migrate.tokenize`, longest
name first) and notifies that person once. The page sends the "@Name" it shows the same way, so a
masked name still reaches its person. Every page turns `<@pid>` back into "@Name" as it shows that
person's name now: masked like every name, a removed person's last name (the snapshot's
`mentions`), "@someone" for anyone else. Edit, Copy, Reply, Ask Claude and Propose take that
"@Name" text, never a token. A token counts toward the text limit, and a cut (a reply's excerpt, a
notification's body) never splits one. A rename shows in every mention of the person; a merge
points the merged person's mentions at the kept one. Claude never reads a token: every event in
the log, and a guest's own Claude through `/api/mine/requests`, gets "@Name", or "@someone" where
`digestNames` is off (for a guest's own Claude, where names are masked to that guest).

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

## Inbox

The top bar's Inbox (in the bell's place) lists a person's own requests, newest first, with the
status they see: `waiting`, `running`, `answered`, `unshared` (a guest's answer before the owner's
Share, shown as "Answered, waiting for the host to share"), `shared`, `declined` or `failed`. The
owner's also lists what waits on them under "Waiting on you": requests to run, results to share,
open problem reports, merge requests and join requests. The snapshot's `inbox` carries these
items, built by `session.py` for the viewer alone (never another person's request or a result its
requester cannot see). `inboxSeen` in `state.json` keeps, per person, the status each item had
when they opened it; an item whose status moved since is unread, and only
`POST /api/inbox/read {keys}` (keys of the caller's own Inbox; others mark nothing) marks one
read. Notifications stay under the Inbox; its badge leaves out the `request` kind, which its
items already show. The owner gets no `queue` line for what its Inbox lists as waiting
(requests, shares, reports, merges, joins); queue lines for proposals, suggestions and upload
offers still count. The owner's own requests skip the queue: one starts running when
sent, and Claude's result for it is shared at once. A guest's request, the owner's guest identity
included, still waits for Run and Share.

## Discussion

Each question has a Discussion under its Claude section, folded by default; its head counts the
comments and those new to the viewer. `state.json` keeps `discussions` (qid -> comments) and
`discussionSeen` (pid -> qid -> the newest comment time they saw when they last opened it); others'
comments after that mark are new. Routes, each one write a second per person and route, and each
writing nothing when nothing would change:

| Route | Body | Who and what |
|---|---|---|
| `/api/discussion` | `{qid, text}` | Anyone who may write. "@Claude" in the text also files an ask request with it (`request` on the comment), owner-gated like any guest request; the owner's own runs at once. It shares `/api/request`'s one a second. Too soon after a request, or with too many requests waiting, the comment still posts, with `requestRefused` and no request. A person keeps at most 30 comments on a question (hidden ones count); a question at most 200 and the session at most 2000 that everyone sees. People already in that Discussion get a rolled-up `discussion` notification; a mention notifies as usual. Posting marks the Discussion read for its author only when no one else's comment is unread to them |
| `/api/discussion/edit`, `/delete` | `{qid, id, text?}` | The comment's author only; another person's comment reads as 404. A comment that filed a request cannot be edited (409 `sent-to-claude`); deleting it leaves the request as it is |
| `/api/discussion/hide` | `{qid, id, on}` | Owner only. A hidden comment leaves every other snapshot and the digest; its author still sees it, with `hidden`. A request it filed that still waits is declined, as by the owner's Decline |
| `/api/discussion/react` | `{qid, id, emoji, on}` | The chat's emoji set and caps |
| `/api/discussion/read` | `{qid, at}` | Marks the Discussion read up to `at`, never past the newest comment the reader can see; allowed while ended |

The round's digest lists each question's comments under `discussion` (`text`, `by` with
`digestNames`, `edited`, `askedClaude`), hidden ones left out: the newest 50 at most, each cut to 500
characters, within 30000 comment characters per digest; `discussionMore` counts the rest.

## General asks

A request about the whole session names no question: "@Claude" as a word in a chat message (the message then
carries `request`; the composer says so), or `POST /api/request` with `scope: "session"` in place of `qid`, Ask
Claude's pinned "About the whole session". It runs only on the host's Claude, waits for the owner's Run like any
guest request (the owner's own runs at once), shares the request route's one a second and the waiting cap, and a
message whose request is refused still posts with `requestRefused`. Chat has no edit, delete or hide, so nothing
else applies. `request-run` lists it with `scope: "session"` and no `qid` or `question`, plus `from: "chat"` when a
message asked; the `result` op answers it with no `qid`, and its result is kept under `results.session` with no
`qid`, so a file from before loads as it is. Once shared (the owner's own at once), the result is also Claude's
chat message: the host's, marked `claude: {result}`, replying to the asking message while chat keeps it; the
result's `msg` names it. Reactions and replies to it tell no one, and it cannot become a proposal. The Inbox, its
toasts and the Run cards say General, or "about the session", where they name a question; the owner shares it from
Ask Claude on "About the whole session", which lists those answers. A digest result carries `scope: "session"` in
place of `qid`.

## Connect your Claude

A guest can run a request on their own Claude instead of the host's (R2-12; Brief C18-C20): in
Ask Claude, "Run it on my own Claude" sends `POST /api/request` with `runner: "self"`. Such a
request never enters the owner's queue, never makes an event or a notification (a mention in it
tells nobody), and is read, claimed, answered or failed only by its requester, with their secret
or their watcher key, through `GET /api/mine/requests[?status=]` and
`POST /api/mine/requests/{claim,result,fail}` (another person gets 404 `no-such-request`; one
write a second per route). Its result, marked `by: guest-claude`, waits for the owner's Share
like every result: until then only the requester ("Only you and the host see this until the
host shares it") and the owner see it. The owner can also take a shared one down (`discard`);
a removed guest's results leave every view and the digest. Shared, it shows as "Answer from
Ann's own Claude", via "their own Claude" whatever tools it names in `used`, and reaches the
round's digest with `from: "guest-claude"` (and `by` when `digestNames` is on). Nobody else
ever sees the request text.

Bounds (session.py, judgment): running self requests count toward `MAX_PENDING_REQUESTS`; one
person's own Claude posts at most `MAX_MY_RESULTS` results on a question and
`MAX_MY_ROUND_RESULTS` in a round, and at `MAX_RESULTS` across the session a new one is refused
(409 `results-full`), never one dropped. A digest lists at most `MAX_DIGEST_RESULTS` results and
`MAX_DIGEST_CHARS` summary characters; the rest are counted in `resultsMore` ("N more on the
page"). A person has at most `MAX_MY_PROPOSALS` proposals waiting (429 `too-many-pending`) and
the session holds at most `MAX_PROPOSALS` (429 `too-many-proposals`); a digest lists at most
`MAX_DIGEST_PROPOSALS` new proposals and counts the rest in `proposalsMore`, which a later digest
lists.

The **watcher key** is what a guest pastes into their own Claude, never their session secret:
`POST /api/watcher` issues a random one (replacing any earlier one; `state.json` keeps its sha256
under `credentials.watchers`), `POST /api/watcher/revoke` ends it, and the snapshot's
`me.watcher` says whether one exists. Sent as `X-Watcher-Key`, it works only on the four
`/api/mine/requests` routes, for its person's own requests; every other route answers it 401,
as it does a key sent as `X-Session-Secret`. Removing, declining or merging a person drops it, so a
restored person copies a new one. The owner gets none (403 `guests-only`).

A digest lists each shared result once, in the first round sent after the owner shared it
(`publishedAt`, else `at` for a result shared before that field existed).

`web/connect.js` builds everything surface-specific; the server knows only `runner: self`:

- **Watcher** (Claude Code, or Claude Desktop's Code tab): a prompt that polls the guest's pending
  requests at the address they opened the page on, claims each, and posts the answer. It holds no
  key; Claude asks for the watcher key, which the guest copies with "Copy watcher key" and ends
  with "Revoke watcher key".
- **One request** (any Claude, including Desktop chat and claude.ai on the web): "Copy prompt" (or
  "Open in Claude Desktop"), then "Paste answer"; trailing `Title - https://...` lines become
  sources.
- Both prompts frame the session's text as data with the untrusted-content spine
  (`docs/conventions/untrusted-content/README.md` in the marketplace repository). The one-request
  prompt quotes it between `--- SESSION DATA <marker> ---` lines whose random marker is new per
  prompt and named in the framing line; the quoted text is NFKC-normalized with format
  characters dropped, and anything shaped like a SESSION DATA marker (dashes, spacing,
  underscores or look-alike letters aside) becomes `[marker removed]`.
- Links use only `claude-cli://open?q=`, `claude://code/new?q=` and `claude://claude.ai/new?q=`,
  the prompt through `encodeURIComponent`. A link longer than its surface's limit is not offered;
  copying still works. Each prefills the prompt and sends nothing until the guest presses Enter.

Upstream link formats (volatile; read the pages, never copy their limits here):

- Claude Code `claude-cli://open` and its `q` limit: <https://code.claude.com/docs/en/deep-links#build-a-link>.
- Claude Desktop `claude://code/new` and `claude://claude.ai/new`, and their `q` limit:
  <https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link>.
- claude.ai on the web documents no prefill link, so the web uses Copy prompt.
- As of 2026-10-17. Recheck when either page changes a format or limit, when claude.ai documents a
  web prefill link, or when a link opens with its prompt sent rather than filled in.

## Uploads

Off until the owner turns on Uploads (`shared_session.uploads`). The answer composer's attach button
then offers "Upload a file", and lists the person's files the owner accepted, which an answer or a
pick carries (C44, at most four; `attachments` on `POST /api/answer` and `POST /api/pick` replaces
the list, left out it is kept). While Uploads is off no upload control shows.

1. `POST /api/upload/offer` `{file, size, type, qid?, thumb?}` (96 KB) records the offer; the file
   stays in the browser (IndexedDB, or memory where a private window refuses it) until the owner
   accepts. The owner's own offer is accepted at once.
2. The owner accepts or declines in the Host queue (`POST /api/upload/act`); the uploader can
   withdraw. Declined or withdrawn, the browser deletes its copy and shows "Not accepted" or
   "Withdrawn", and whatever arrived is deleted. Removing a person declines each of their files
   not yet received (`why: removed`) the same way.
3. Accepted, the browser sends the file in order as raw pieces (`POST /api/upload/chunk`,
   `application/octet-stream`, 8 MiB each, below the quick tunnel's 100 MB request limit) with
   `X-Upload-Id`, `X-Chunk-Index`, `X-Chunk-Total`, `X-Chunk-Sha256`, and `X-File-Sha256` on the
   last. A piece the server has is answered `{received}` unread; one past the next is 409
   `chunk-gap` with `received`, so a reload or a dropped connection resumes from there.
4. The last piece makes the file `done` under `uploads/accepted/` (on Windows marked as from the
   internet, `Zone.Identifier` with `ZoneId=3`) and writes `upload-received` (`upload`, `file`,
   `stored` relative to the data folder, `qid`) for Claude.

Limits: 10 open files per person; 100 MB per guest, counted over every file of theirs not
declined, withdrawn or failed, received ones included, so it is a total, not a per-file size; 5 GB
per session over accepted files only (accepted, uploading or done), so offers alone never fill it,
checked again when the owner accepts (`upload-too-large`, field `accept`). Previews keep at most 256,000 characters per person and 1,000,000 per
session; past that an offer keeps none. Every piece read counts against the one-a-second throttle,
damaged or not. Guests send pictures, PDF, text, CSV, RTF and Office files; the owner and trusted
guests any kind. The first piece must start as its kind does (PNG, JPEG, GIF, WebP, PDF, RTF, OLE
and ZIP magic numbers; UTF-8 without NUL for text) or the upload fails and its bytes are deleted; a
damaged piece (its sha256) is refused and sent again; a whole file whose sha256 differs fails and
is deleted. An Office Open XML, OpenDocument or zip file is read from its central directory once it
is whole: OOXML must hold `[Content_Types].xml`, OpenDocument must start with a stored `mimetype`
naming its kind, no entry name may be absolute or hold `..`, it may unpack to 1 GiB at most, and no
entry over 1 MiB may pack tighter than 100 to 1; otherwise it fails and is deleted. A display name
loses control, format (bidi), private-use and unassigned characters, and the owner's queue shows
the server's extension beside it.

Nothing uploaded is served back: the files sit in the private data folder, named by the server
(`uploads/pending/<32 hex>`, then `uploads/accepted/<yyyymmdd>-<upload id>.<ext>`); the person's
file name is display text only. The snapshot never carries a path: `myUploads` (one's own),
`uploads` (the owner's, with a picture's preview) and `files` (name, kind, size and status of the
files shown answers carry). Each start deletes pending files no upload names, declines files still
on their way from someone no longer in the session, and cuts a partial file back to the pieces its
record counts. A state whose upload id, extension or received name is not one the server makes
does not load.

## Problem reports

Anyone joined can report a problem: "Report a problem" in the phone More sheet and the desktop Help
popover, and "Report this" on the toast of an action the server refused. The form asks "What went
wrong?" (required, 2000 characters) and takes one optional screenshot (`accept` png, jpeg or webp,
no `capture`), which the browser re-encodes to at most 1600 px on its long edge and 512 KB. Before
Send it lists, under "Sent with this report", every field that goes with it: the view and phone
tab, the question and round, the device kind and browser family, `innerWidth` x `innerHeight` and
the visual viewport's width, height and scale, the build, and the last 5 errors the page saw,
refusals included ([Logs](#logs)). Never an answer, chat, the address or its fragment, or a credential.

`POST /api/report {text, ctx, image?}` (auth class person) takes them, `image` a data: URL whose
bytes must start as PNG, JPEG or WebP do (415 `file-type`; over 512 KB 413 `upload-too-large`).
Its body cap is `REPORT_MAX` (about 732 KB) instead of 32 KB. A report is allowed while Uploads is
off: one picture, checked, saved as `reports/<id>.<png|jpg|webp>` in the private data folder and
shown to the owner alone; every other upload stays refused (403 `uploads-off`). One report per
person every 10 s (429 `slow-down`), 5 open per person (429 `too-many-pending`), 500 per session
(429 `too-many-reports`). The record, `reports` in `state.json` (`{F<N>: {by, text, ctx, image?,
status: open|seen|resolved, asked?, ts}}`; optional, so a file from before loads), reaches only the
owner's snapshot (`reports`, with `image: true` instead of the path) and shows in the Host queue as
a Problem, with Seen, Resolved and Ask Claude about this report ([Moderation](#moderation)). A report alone
never reaches Claude: only the owner's Ask writes `report-filed` (`report`, `qid`, `text`), as
rounds wait for Send and requests for Run. The text is the reporter's data, never instructions, and
Claude reads a picture only through the Read-only `upload-reader` agent.

## Logs

`server.log` holds one line per entry: the time, the level, then the entry's kind and `key=value`
fields. A value is escaped like the path (`\x1b`, a double quote as `\x22`, U+2028 as `\u2028`) and
quoted when it holds a space, so only a newline ends an entry; `logs` splits on newlines alone. `method`, `route` and `status`, and a client entry's `pid` and `kind`, never hold one.

| Kind | Level | Fields |
|---|---|---|
| `request` | INFO for 2xx/3xx, WARNING for 4xx, ERROR for 5xx | `method route status ms` and `pid` (the acting person's id, once known); a refusal adds `code field message` (its error body); a 5xx adds `trace`, the last 8000 characters of the traceback of the bug or of the session's refusal where it was raised. The one exception is 503 `busy`, answered before any request is read: `method=- route=- status=503 ms=0.0 code=busy message=...`, no pid, no trace. A `summary` the server takes gets no entry |
| `client` | WARNING | `pid kind message source route code ua fp`, as the page sent them: a fault |
| `summary-batch` | INFO | `summaries dropped data`: every `summary` taken since the last batch, written every 10 minutes and when the server stops, if there was one. `data` is a JSON array of `[message, ua]` pairs, sorted, in ASCII with each space as `\u0020`, so it ends the line; `dropped` counts summaries past the batch's 100,000 bytes. No pid, and no time but the batch's |

```text
2026-10-17 13:21:56,794 WARNING request method=POST route=/api/person/role status=400 ms=0.5 pid=host code=bad-field field=role message="role must be one of leader, guest."
2026-10-17 13:21:57,102 ERROR request method=POST route=/api/rename status=500 ms=1.2 pid=pidAnn001 code=state-invalid message="The server could not do that; nothing was written." trace="Traceback (most recent call last):\x0a  File \x22...\x22 ..."
2026-10-17 13:21:58,330 WARNING client pid=pidAnn001 kind=error message="TypeError: x is undefined" source=/app.js:12 route=/ ua="chrome computer" fp=1a2b3c4d
2026-10-17 13:30:00,412 INFO summary-batch summaries=1 dropped=0 data=[["pv=0a1b2c3d\u0020lat:/api/vote=0,3,1\u0020rb:/api/vote=1\u0020gap=900\u0020rep:1a2b3c4d=2\u0020inp=184:pointer:vf-vote\u0020lcp=1200:vf-qtext","safari\u0020phone"]]
```

A pid is no credential. No entry holds a token, secret, guest key, owner link, request body, answer
or chat text, or upload.

**What the page records** (`web/core.js` telemetry). Faults go out at once, under the person's pid
so they can be matched to that person's request entries, the first time each fingerprint (`fp`)
shows; after that each repeat is a count in the next summary:

- `error` and `rejection`: a script error (`source` as `/file:line`) or an unhandled rejection.
- `api`: an action that never reached the server: `code` `network` (the request failed) or
  `no-answer` (an answer without the server's `X-Shared-Build` header, such as the tunnel's own
  error page). A refusal is logged once, by the server's `request` entry; the page keeps it only
  for a problem report.
- `layout`: an anomaly, `anomaly=overflow` (the page, or a pane that scrolls up and down, is wider
  than it shows), `field-hidden` (a focused field outside what the keyboard leaves visible) or
  `header-off` (the header above the visible area), each with `at` and `el` component names (the
  nearest `vf-` or `core-` class) and numbers; logged when it appears. The phone keyboard readout
  is also `layout`: once per sheet opening, one `name=value` line of numbers and CSS values.

When the page hides it sends one `summary` with no pid, which reaches the log only in the next
`summary-batch`: the page sends it as it sends a heartbeat, whose request entry names the person,
so a summary with a time of its own could be matched to them. A summary holds `pv`, a random id for this page view so a
page's INP counts once; `owner=1` on the owner's page; `lat:<route>` tap-to-answer counts per
bucket (upper edges 100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000 and 10000 ms, then above),
measured with `performance.now()`; `rb:<route>` optimistic changes rolled back; `gap`, ms from the
page showing again to its first good poll; `rep:<fp>` repeats; `inp` (ms, interaction type,
component) and `lcp` (ms, component) from the vendored web-vitals build, the component `-` where
web-vitals names its target by a selector or an id instead (an element gone before it measured), or `inp=missing`,
`lcp=missing`, `vitals=missing` where the browser API or the file is missing. What does not fit in
500 characters waits for the next summary. Nothing is sampled.

Never recorded: what anyone types, answers, chat, names, the address or its fragment, text on the
page, or a credential. Help says so in one line, with a "What this page records" link to the plain
list; the phone More sheet opens the same list. Recording has no off switch: every joined page
sends, and a `telemetry` key an older page left in `localStorage` is ignored. The join dialog shows
only its heading, the invite line, the name prompt, the name box and Join.

`POST /api/client-log` (auth class person) takes `{kind, message, source, route, code, ua, fp}`:
strings, at most 500 characters for `message`, 200 for `source` and `route`, 60 for `code` and
`ua`, 16 for `fp`; `kind` (`error`, `rejection`, `api`, `layout`, `summary`) and `message`
required. It answers `{ok: true}`, or 401 `unknown-session` without identity (a page that has not
joined sends nothing), 413 `body-too-large` over 4096 bytes, 400 `bad-field` for another key or a
wrong type, 400 `too-long`, and 429 `slow-down` past 20 faults or 6 summaries a minute from one
person (two buckets, so neither starves the other). A summary the server takes has no `request`
entry; a refused one has one with no pid. The server holds taken summaries in memory until their
batch: a crash loses them, and so does `share.sh stop` on Windows, which ends the process at once.

`share.sh logs --summary` (add `--json` for one JSON line, `--since MINUTES` to narrow) adds the
log up: the top 10 error fingerprints with counts, first and last seen (`firstSeen`, `lastSeen`,
to the second) and device and browser classes, refusals by route and code (from the
server's entries), network failures and unanswered actions by route, tap-to-answer p50 and p95 by
route (the upper edge of the bucket) beside the server's own `ms`, rollbacks and their rate,
reconnect gaps (over 10 s, worst, by device), layout anomalies by device kind, INP and LCP p75 by
device with the count of page views missing the API, and how many summaries came in how many
batches from how many page views, and how many were dropped.
The owner's own page views stay out of the timings. A summary counts at its batch's time, for
`--since` and for a fingerprint's last repeat. `logs --errors` leaves batches out.

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
| `.shared-tunnel.json` | `tunnel.py` | 0600 | `{pid, url, port, startedAt, marker, processStart, adopted}` |
| `cloudflared.log` | cloudflared | 0600 | Its output, where its address is read |
| `server.log` (+ `.1`..`.3`) | server | 0600 | One entry per request and per page error report ([Logs](#logs)); rotated at 1 MB, 3 kept |
| `.shared-server.err` | the server's stderr | 0600 | Why a start failed |
| `.shared-reported` | `share.py` | 0600 | The guest link the last `ensure-running` printed (for `shareChanged`) |
| `.watch-seq`, `.watch-replay` | `watch.sh` | | |
| `assets/<16 hex>.<ext>`, `assets/.<id>.json` | server (`add-asset`) | | The file, and its kind, size and scale |
| `uploads/pending/<32 hex>`, `uploads/accepted/<yyyymmdd>-<upload id>.<ext>` | server | 0700 folders, 0600 files | An accepted upload's pieces so far; a received one (see [Uploads](#uploads)). Never served |
| `reports/<report id>.<png\|jpg\|webp>` | server | 0700 folder, 0600 files | A problem report's screenshot ([Problem reports](#problem-reports)); only the owner's `GET /api/report/image` reads it back |

Every `GET /api/state` with identity carries `schemaVersion`, `rev` and `build` (a hash of the
served web files); every answer carries `X-Shared-Build`. A page built for another version or
build reloads itself. Its `ETag` moves with `rev`, presence and a 5-second clock tick (so an
offline or away person shows without a write); a heartbeat that changes nothing anyone sees moves
nothing. A poll whose `If-None-Match` differs only in presence or the tick gets `{rev,
presenceOnly: true, serverTime, presence, lastSeen}` (`wire.schema.json` `presenceOnly`), and the
page keeps the rest of its last snapshot.

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
  | Stored chat, notes, suggestions | the newest 2000 messages (a snapshot carries the newest 50, `GET /api/chat` at most 100 at a time); 2000 notes, then a new one is refused (409 `notes-full`); 200 suggestions per question, with votes on a dropped one dropped too |
  | Connections served at once | 64; one more is answered 503 `busy`, then read until it closes (at most 64 KiB and 2 s, 8 such connections at once) so the close does not reset it and drop the 503 |

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
  control characters escaped (`\x1b`, `\x0a`); never a header value, request body or upload
  ([Logs](#logs)).
- **What a visitor reads.** Without identity, `/api/state` is `{title, ended, joinNeedsKey,
  schemaVersion}` only; a removed person and an owner link from before a rotation read nothing.
  Results stay hidden from guests until the owner publishes them.
- **Guest text is data.** Answers, chat, proposals and requests reach Claude in the digest,
  delivered with session-bridge's data note; an instruction in them is a finding, never a request.
- **Files.** `add-asset` reads only regular files under the data folder with no hidden folder or
  name below it, and only when the bytes are an allowed type. Claude saves captures in
  `<data_dir>/staging/` (0700); the system temp folder is refused.
- **Name hiding.** When the session shows initials or "someone", a join never answers `was` (the
  earlier person with the same name) and keeps the name as typed, with no " 2" suffix for a taken
  one, and a nameless join's "Guest N" ignores typed names, so two people may share a name and a
  join cannot probe for hidden names. A guest's `@Name` stays plain text rather than pointing at a
  person, also after the owner edits that answer or request, so a guest's own text never pairs a
  name with a pid; the owner's and leaders' own mentions still point, except to a name two people
  share, which stays text. The Host view's people list numbers people who share a name, in join order,
  and the owner's own name still takes a suffix.
- **Personal links.** A `#me=` link opened in a browser that already holds a different guest
  secret asks "This link signs you in as someone else on this device. Switch?", with Keep the
  default; only Switch replaces the stored secret, so a link someone hands over cannot sign a
  device in as them silently. With no secret stored, the link signs in at once.
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
| Watcher key | The guest's clipboard and their own Claude's context, where they paste it; the `X-Watcher-Key` header, which Cloudflare's edge sees. It reads and answers only that guest's own self requests |
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

`tests/bench_snapshot.py` seeds 20 people and 500 chat messages, then measures what one guest
page reads in 30 idle seconds while every page beats. On the development machine the guest
snapshot is 13,368 bytes (1,939 gzip; 84,106 and 7,604 when it carried every message), and the
idle page reads 384 bytes a second: 14 polls answer 304 and 6 presence only (56,070 bytes a
second, all 20 polls the full snapshot, when every heartbeat moved the ETag). The server sends no
gzip.

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
node plugins/planning/shared/tests/ui_chat_history.js
node plugins/planning/shared/tests/ui_lists.js
node plugins/planning/shared/tests/ui_moderation.js
node plugins/planning/shared/tests/ui_acceptance.js
node plugins/planning/shared/tests/ui_proto.js
node plugins/planning/shared/tests/ui_connect.js
node plugins/planning/shared/tests/ui_uploads.js
node plugins/planning/shared/tests/ui_report.js
node plugins/planning/shared/tests/ui_general.js
bash plugins/planning/shared/tests/align.test.sh
```

`ui_connect.js` checks Connect your Claude for a desktop guest and a 390x844 phone guest: the
watcher and Desktop chat links and their decoded prompts, Copy prompt, Paste answer, the answer
marked as the guest's own Claude and held for the owner's Share, a watcher's round trip with a
watcher key and its revoke, the owner taking a shared answer down, that the owner and another
guest never see the request and another key cannot answer it, and that on the phone every Connect
control lies inside the viewport. Before the browsers it checks the one-request prompt's data
block against look-alike end markers.

`ui_uploads.js` checks uploads with a 390x844 phone guest and a desktop owner: no upload control
while Uploads is off, an offer held in the guest's browser, the owner's Accept, a chunked send
that resumes after a dropped piece and a reload, the file attached to a pick and shown to another
guest, and a declined file deleted from the browser and shown as "Not accepted".

`ui_report.js` checks Report a problem with Uploads off: on a 390x844 phone from More, the sent
list before Send, a 3200x1800 screenshot re-encoded to 1600 px, the field and Send report above a
keyboard, and a request carrying no answer, chat, fragment or secret; the desktop owner's Problem
item, its picture, Ask Claude about this report (the owner's alone), Seen telling the reporter, and
Resolved; on a desktop, Help's entry and a
refused action's "Report this", whose form lists the refusal. `ui_layout.js` also sweeps the form
with keyboards at 320 to 430 px wide.

`ui_proto.js` checks the prototype page on a desktop and a 390x844 phone in separate browser
contexts: the preview tile and its link, the variant switcher, Annotate, a note pinned to an
element of an html variant and to a spot of a picture, the notes in the Claude thread and the
digest, the variant's sandbox, and a forged pin message being ignored.

`ui_layout.js` checks no page scroll at five sizes and 200% zoom in both themes, 44 px phone
targets, no sideways scroll in Ask Claude on a phone with "Run it on my own Claude" on, the
answer box right under the question, a guest's first view (goal, the host's ask,
"Start here: question 1"), the ten person colors against WCAG 2.2 AA, and the phone edit sheet.
`ui_keyboard.js` checks focus traps, Escape, focus return, announcements and the first-visit tour
(the `tour` pref). `ui_inputs.js` types 2000 characters and pastes a 300-character word into each
input surface on iPhone and Pixel profiles at keyboard-open heights and on a desktop. `ui_chat.js`
checks the host's unread badge, a frozen tab catching up, and the new-messages pill.
`ui_chat_history.js` seeds 120 messages and checks the 50-message window, a notification and a
reply quote opening a message outside it, "Load earlier messages" from the keyboard, scrolling up
keeping the reader's place, and 60 messages that arrive while frozen all counted unread.
`ui_lists.js` checks with 30 guests the default counts and Show more of answer cards, people,
the queue, notifications (with Unread only), proposals, Later and suggestions, the people
chips and name search, and the chips on a 320 px phone.
`ui_moderation.js` checks the intro before question 1 and from the header, a phone's first screen
with the intro folded, Hide and Edit with the owner-only history, chat reactions, the owner's
per-person view, and Approve new joins. `ui_acceptance.js` checks the Brief acceptance criteria no other
suite drives in a browser: the join note and a refused join, Claude's take, the round states and toasts, Follow,
Reconnecting, the new guest link, the ended session, the Host view per role, the phone header and height, and
the views sharing data.
`align.test.sh` (about 3 minutes) is the C41 pixel pass over 49 views; `ALIGN_VIEWS` and
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
