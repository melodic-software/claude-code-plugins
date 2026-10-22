# Shared interview session

The runtime behind the interview skill's shared lane (`skills/interview/context/lane-shared.md`):
one person, the owner, runs a multi-person interview from their own machine. Guests open a
Cloudflare tunnel link (a quick tunnel, or a [named tunnel](#a-stable-guest-link-the-named-tunnel)); the owner's Claude session drives the session through `share.sh`
and the session-bridge watcher. Python 3 standard library only.

## Files

| File | Job |
|---|---|
| `share.sh` | Launcher: runs `share.py` with the first Python 3 that runs. The session-bridge `CONTROL` script and the only file the skill calls |
| `share.py` | The CLI: `ensure-running`, `stop`, `restart`, `status`, `url`, `list`, `apply`, `lease` |
| `server.py` | One process, two 127.0.0.1 listeners: the guest listener (the page and `/api/*`) and the control listener (session-bridge). Routes, auth, caps, headers and the snapshot; no domain rules |
| `session.py` | The domain rules over `state.json` (people, rounds, questions, votes, locks, proposals, requests, results, uploads, digest, ops) |
| `tunnel.py` | cloudflared: start (quick or named), address parse, reattach, adopt, exit detection, a switch's retired tunnel, stop. The only file that runs cloudflared |
| `cfdns.py` | The owner's Cloudflare checks for a named tunnel: the zone listing, the planned DNS record and its confirm-gated write, the machines running the tunnel |
| `detached.py` | Processes that outlive their starter, and liveness and stop by pid, on Windows, macOS and Linux |
| `session_bridge.py`, `watch.sh`, `wake.sh` | Generated copies of `lib/session-bridge/` (`scripts/sync-shared-copies.sh`); edit the canonical, never these |
| `session-bridge.conf` | `NAME=shared`, `CONTROL=share.sh` |
| `schema/*.schema.json` | The persisted and wire shapes: `state`, `ops`, `event`, `question-shape`, and `wire` (the heartbeat body and a presence entry, kept only in memory) |
| `web/` | The page, served from a fixed allowlist (`/`, `/core.js`, `/app.js`, `/connect.js`, `/core.css`, `/app.css`, `/proto.js`, `/web-vitals.attribution.iife.js`), plus `/proto/<qid>` (`proto.html`) for a prototype question; `proto-pin.js` is served only inside an html variant (see [Prototype page](#prototype-page)). `core.js` is the only code that talks to the server: it polls `/api/state?since=<rev>`, reloads the page when the build changes, builds the state `app.js` reads, and words errors by their code. The guest secret stays under the prototype's `localStorage` key, `secret`. `web-vitals.attribution.iife.js` is the web-vitals 6.2.3 attribution build, copied unedited from its npm package, with that package's Apache-2.0 license beside it as `web-vitals.LICENSE` (not served). `web/harness.html` is test-only and off the allowlist: `ui_inputs.js` serves it into the page's origin from the browser |
| `tests/` | `test_session.py`, `test_server.py`, `test_share.py`, `test_tunnel.py`, `test_cfdns.py`, `test_load.py`, `test_schema_shapes.py`, `tracer.test.sh`, `tracer-live.test.sh`, `ui_journey.js`, `ui_formats.js`, `ui_presence.js`, `ui_layout.js`, `ui_keyboard.js`, `ui_inputs.js` (with `harness-open.js`), `ui_chat.js`, `ui_chat_history.js`, `ui_lists.js`, `ui_proto.js`, `ui_proto_versions.js`, `ui_connect.js`, `ui_uploads.js`, `ui_report.js`, `ui_clientlog.js`, `ui_telemetry.js`, `ui_advance.js`, `ui_speech.js`, `ui_askbox.js`, `ui_myreports.js`, `ui_welcome.js`, `ui_review.js`, `ui_move.js`, `test_people_proposals.py`, `ui_claude_proposals.js`, `align.test.sh` (with `align.js`), `bench_snapshot.py`, `browser_harness.js`, and `fixtures/` (incl. `fake-cloudflared.sh` and `fake_cloudflared.py`) |

## Run

```bash
bash '<plugin-root>/shared/share.sh' --dir '<data_dir>' ensure-running --open --defaults-file '<data_dir>/defaults.json'
```

Every command prints one JSON line on stdout and diagnostics on stderr. On Windows,
`python share.py --dir <data_dir> ...` runs without bash.

| Command | Args | Output |
|---|---|---|
| `ensure-running` | `[--open] [--defaults-file F] [--guest-port N] [--adopt-tunnel PID URL] [--tunnel-hostname H --tunnel-token-file F]` | `{ok, guestUrl, localUrl, ownerLinkFile, shareChanged, resumed, tunnel, watch}`: starts or reuses the server and the tunnel; `tunnel` is `quick`, `named` or `down`. `--tunnel-hostname`: see [A stable guest link](#a-stable-guest-link-the-named-tunnel). A new session's `state.json` comes from `defaults.json` (`{"settings": {...}}`, state.schema field names). `--guest-port` applies only when the session is created; later starts reuse the recorded ports. `--adopt-tunnel`: see [Adopting a running cloudflared](#adopting-a-running-cloudflared) |
| `stop` | `[--keep-tunnel]` | `{ok, stopped}`: ends the armed watcher, the server and cloudflared (an adopted cloudflared keeps running; see [Adopting a running cloudflared](#adopting-a-running-cloudflared)); keeps the ports and the state. `--keep-tunnel` keeps the guest link for the next start |
| `restart` | | Stops and starts the server only, on the same ports, with the same control token: the tunnel, the guest link, the state and an armed watcher all survive. Open pages see the new build and reload |
| `status` | | `{ok, running, tunnel, guestUrl, round, intro, people, queue, unhandled, lease}`; `intro` is true once "Why you're here" is set |
| `url` | `[--owner]` | `{guestUrl}`, or `{ownerUrl}` (a credential, printed only on request) |
| `list` | `--root '<memory_dir>'` (no `--dir`) | `{sessions: [{dir, title, running, guestUrl, round, ended}]}` |
| `apply` | `--file F` | `{ok, results}`; deletes `F` once it applies. A missing `F` is a no-op, so `wake.sh` re-arms with nothing to write |
| `lease` | `[--release]` | `{lease}` |
| `logs` | `[--errors] [--since MINUTES]` | `{ok, lines}`: the newest 200 lines of `server.log` and its rotated files, oldest first; no server needed. `--errors` keeps refusals, server errors and client entries. See [Logs](#logs) |

Exit codes: 0 done; 1 refused (bad arguments, a state file that does not load, a `--guest-port`
or `--adopt-tunnel` on an existing session, an adopted pid
that is not a running cloudflared to the guest port, a tunnel hostname or token file that cannot
serve); 2 a prerequisite is missing (Python 3, curl,
cloudflared) or the server cannot start or be reached, a busy `--guest-port` or named-tunnel port included; 3 no tunnel
address in time (the server keeps running on `localUrl`, `tunnel: "down"`).

The tunnel is its own detached process and outlives server restarts. The server checks it every
second: when cloudflared exits, the server starts a new one (backing off up to a minute while it
fails), allows the new host, and records the new link in `session.share` with `changedAt`, which
the owner's view shows as "New guest link, share again"; the next `ensure-running` says
`shareChanged: true`. `python tunnel.py adopt --dir D --pid N --url U --port P` records a
cloudflared that is already running, without starting anything; it is then watched and restarted
like one the server started.

## Adopting a running cloudflared

```bash
bash '<plugin-root>/shared/share.sh' --dir '<data_dir>' ensure-running --guest-port <port> --adopt-tunnel <cloudflared pid> <tunnel URL>
```

Creates a session on `<port>` and records the running cloudflared as its tunnel, starting nothing, so
the guest link stays the same; it is then watched like the server's own. The flags may instead be
`defaults.json` keys, `guestPort` and `adoptTunnel: {pid, url}`, which apply only when the session
is created. `ensure-running` needs cloudflared on PATH even so. `--adopt-tunnel` needs
`--guest-port`, the port that cloudflared points at, and refuses (exit 1) a pid whose program file
is not `cloudflared` (`cloudflared.exe` on Windows) or whose one `--url` is not
`http://127.0.0.1:<port>` or `http://localhost:<port>`, or cannot be read. The session never
signals an adopted cloudflared: `share.sh stop` drops its record and leaves it running; end it
yourself (`kill <pid>`, or `Stop-Process -Id <pid>` on Windows) to close the link. If it exits, the
server starts a cloudflared of its own (a new link), which `stop` ends like any other.

## A stable guest link: the named tunnel

A quick tunnel's address changes whenever cloudflared restarts, a reboot included. A named tunnel
keeps one address, `https://<tunnel_hostname>`, across restarts, so guests keep their link and,
because their browser storage belongs to that address, their identity. It is opt-in per machine
through two planning plugin options, set in that machine's user settings (`pluginConfigs`):

| Option | Value |
|---|---|
| `tunnel_hostname` | The tunnel's public hostname, such as `interview.example.com`. Empty (the default) keeps the quick tunnel |
| `tunnel_token_file` | Absolute path of a file holding the tunnel's token, readable only by you. The token itself never goes in settings, a repository or dotfiles |

The skill passes them as `ensure-running --tunnel-hostname H --tunnel-token-file F`; an
`ensure-running` without `--tunnel-hostname` keeps the tunnel the session already runs, and only an
empty `--tunnel-hostname ''` goes back to the quick tunnel. share.py
checks the file (it exists, is not empty, and no other user can read it) but
never reads it: cloudflared does, through
[`--token-file`](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/run-parameters/)
(cloudflared 2025.4.0 or later), so the token is on no command line and in no output. Neither cloudflared nor the server inherits `TUNNEL_TOKEN`,
`TUNNEL_TOKEN_FILE`, `CLOUDFLARE_API_TOKEN` or `CF_API_TOKEN` from the shell that starts them. A named
session's guest port is fixed: `--guest-port`, else 8765, and a busy port refuses the start
(exit 2) instead of moving, because the tunnel's ingress rule names that port. The token file must
stay in place while the session runs: the server restarts cloudflared from it whenever cloudflared
exits.

**One machine per tunnel.** Every machine running the same tunnel is a replica, and Cloudflare
sends each guest to the nearest one
([Tunnel availability](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/tunnel-availability/)),
so a second machine would serve its own session to some guests. Set `tunnel_hostname` on one
machine only, and before moving the tunnel to another run `python cfdns.py connectors` (below),
which exits 4 when more than one machine runs it. `ensure-running` prints this reminder on every
named start.

**Switching.** Setting, changing or clearing `tunnel_hostname` on a running session switches its
tunnel at the next `ensure-running`; the session keeps its guest port, so switch to a named tunnel
only a session whose port the ingress rule names (the reminder names the port). The switch happens only
once the new address proves it reaches this server: the server fetches
`<new address>/api/tunnel-probe/<nonce>` and expects an answer only it knows, retrying for up to 30
seconds. A hostname that is mistyped, or routes to another machine, is refused (exit 1) with the
old tunnel and its link still running, so no page is ever sent where its guest's secret would leak. The old tunnel keeps running for ten minutes; in that time a
page open on the old address asks the server, learns the new one, and moves there, carrying a
guest's identity as a personal link (`#me=`), so the same browser keeps its name and answers. A
quick tunnel that restarts after a reboot leaves no old page to ask: those guests open the new link
as new people, and the owner can merge each with their earlier self.

### Setting it up once

1. **API token.** In the Cloudflare dashboard, create an API token with two permissions,
   Account > Cloudflare Tunnel > Edit and Zone > DNS > Edit, limited to your account and the one
   zone ([Create an API token](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel-api/)).
   Keep it in your secret store; `cfdns.py` reads it only from the file `--api-token-file` names.
2. **Tunnel.** Create a remotely-managed tunnel (Networking > Tunnels > Create a tunnel, or the API
   steps on the same page), save its token to the file `tunnel_token_file` names, and note its id.
3. **Route.** Publish an application on the tunnel: hostname `tunnel_hostname`, service
   `http://127.0.0.1:8765` (the guest port). The server listens on IPv4 only, so name the address,
   not `localhost`. Use a hostname one level below the zone (`interview.example.com`, not
   `a.b.example.com`): Universal SSL covers only the apex and first-level subdomains
   ([limitations](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/)).
4. **DNS.** The dashboard route creates the DNS record itself. Through the API, check and write it:

   ```bash
   python cfdns.py plan  --zone-id <zone id> --hostname <tunnel_hostname> --tunnel-id <tunnel id>
   python cfdns.py write --zone-id <zone id> --hostname <tunnel_hostname> --tunnel-id <tunnel id> --confirm <tunnel_hostname>
   ```

   Both refuse a hostname that is not the zone's name or under it. `plan` only reads: it lists the zone's records and prints the one record the tunnel needs, a
   proxied CNAME to `<tunnel id>.cfargotunnel.com`, with every record already at that name (none
   means no clash; exit 4 on a clash). `write` lists again and creates exactly that record, only
   when `--confirm` repeats the hostname and nothing is at that name. Taking the zone id as an
   argument keeps the token to the two permissions above.
5. **Set the options** on this machine only, then start the session as usual.

### Per platform

cloudflared install commands per platform are in the plugin's `prerequisites.json`; check
`cloudflared --version` is 2025.4.0 or later.

- **Windows.** The token file's access list may name only you, the file's owner, SYSTEM and
  Administrators; share.py refuses any other entry and prints the `icacls` command that fixes it.
  `python share.py` runs without bash; `python cfdns.py` likewise.
- **macOS and Linux.** `chmod 600` the token file; share.py refuses one other users can read.

## The state file is not versioned

`state.json` holds the shape this build writes, with no version number and no migrations; the last
versioned build wrote `schemaVersion` 7. On load that key is dropped and left out of the next
write; a file below 7 is refused (`state-too-old`): start a new session, or restart it under the
previous build first so it migrates to 7. To go back to an earlier build, add `"schemaVersion": 7`
to `state.json` first. When a later build cannot read a session, start a new one and send its link.

## Ops

`share.sh apply --file <data_dir>/ops.json` takes `{"ops": [...]}`, checked against
`schema/ops.schema.json` before any applies; all land or none does (`{error, op, message}` names
the refused op's index).

| Op | Fields | Effect |
|---|---|---|
| `set-title`, `set-goal` | `title` / `goal` | |
| `set-repo` | `repo` (`owner/name`, `""` clears), `commit?` (40 lowercase hex) | The page links `#N` to `https://github.com/<repo>/issues/N`, and a repository path (`path`, `path:line`) to `https://github.com/<repo>/blob/<commit>/<path>#L<line>` once a commit is set. Every joined person's snapshot carries both; the anonymous view does not. Both are replaced together; no `commit` removes the old one |
| `set-intro` | `intro` (0..600) | "Why you're here", shown to a guest before question 1; empty removes it |
| `open-round` | `questions` (1..8), `placements?` | Closes the `working` round (or starts round 1) and opens the next |
| `close-round` | `placements?`, `reason?` | `working` -> `closed`, no new round |
| `ack-round` | `round` | `sent` -> `working` |
| `result` | `qid?`, `request?`, `kind`, `used`, `why`, `summary`, `sources`, `report` | Stores a result, shared or not as [Sharing Claude's answers](#sharing-claudes-answers) says. No `qid` answers a request about the whole session, which `request` must name (see [General asks](#general-asks)) |
| `fail-request` | `request`, `reason` | `running` -> `failed` |
| `add-reference`, `remove-reference` | `qid`, `reference` / `index` | |
| `add-asset` | `path`, `as?`, `scale?` | Copies a PNG, JPEG, WebP, SVG or HTML file (by its bytes, at most 10 MB) from the data folder, where captures go in `staging/`, into `assets/<16 hex>.<ext>`, named by its content; returns `{id, kind, bytes, at, scale}`. Usable from the next apply; a refused apply removes the files it copied and puts back any sidecar it rewrote |
| `set-purpose` | `qid`, `purpose` | The owner's `/api/question/purpose` rules |
| `set-for` | `qid`, `for` | Who must answer, by name or pid; `[]` asks everyone. The owner's `/api/question/for` takes the same body. A question in `open-round` takes `for` too |
| `make-question-from` | `proposal`, `question` | |
| `propose-merge` | `from`, `to`, `reasons` (1..5), `note?` (0..200) | Proposes that `from` (a new browser) is `to`, someone already here, for the owner's Merge; merges nothing. `reasons` from `same-name`, `was-offline`, `same-device`, `expected`. Neither may be the owner (400 `bad-field`); both must be guests who are in, neither a leader nor trusted (409 `wrong-status`); `from` must be a `person-joined` event's `person` and `to` one of its `sameName` (409 `not-reported`); one open proposal per pair (409 `wrong-status`), none again for a pair the owner dismissed (409 `dismissed`), 200 waiting at once (409 `full`; past 200 in all the oldest answered one goes, never a dismissed one, so 409 `full` too when all 200 wait or were dismissed). See [Claude's merge and admit proposals](#claudes-merge-and-admit-proposals) |
| `propose-admit` | `pid`, `reasons`, `note?` | Proposes letting in one join waiting under Approve new joins, which a `person-joined` event with `waiting` reported, for the owner's Let in; lets no one in. The same refusals |
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
  optional for the rest. The Host view's `behind` (each guest's row says "N to answer this round", and a
  Behind chip lists them) and the page's counts count `_owes`; the digest's
  `people.answered` counts who took part.
- **Late acts.** A vote, back, reaction, Disagree or Pass on a closed round's question is stamped in
  `lateActs` (`{qid: {pid: {round, at}}}`), and the next digest's `late` lists what that person
  holds there, each with `act`. A locked question takes none of them (409 `locked`; Suggest a change
  proposes new text) except a Disagree once its round closed.
- **Possibly reopened.** The first late Disagree each person gives with the locked answer of a
  `decide` question (the answer it was locked on, or the one its locked text was edited from or
  reworded; a lock taken from a suggestion has none) raises "possibly reopened": the owner's Inbox
  gets a `reopen:` item with Keep decision and Unlock, the digest lists it under `possiblyReopened`
  (the locked text, and each Disagree with the locked answer the people who disagreed late hold
  now), and every question whose `dependsOn` names it gets a `possibly-reopened` review
  flag, which everyone sees as "Needs review: Q1 may be reopened". The question, its lock and its
  answers never change on their own. A poll never raises it: a closed poll chose no answer.
  `POST /api/decision/keep {qid}` (owner) keeps the decision: the item goes, so do the
  `possibly-reopened` flags it raised, and the log records it; 409 `not-reopened` when nothing is
  raised. Unlock is the usual unlock, which flags the dependents `unlocked`; Unlock or a change to the
  locked text also ends it, with those flags, and so does taking back the last of those Disagrees
  (logged `withdrawn`). A late Disagree with a rejected alternative is kept and raises nothing. A
  newer late Disagree raises the item again, unread.
- **Digest.** `multi` reports picks per option; `scale` the count per value, the mean (two places)
  and the median; `rank` Borda totals (with n options a first place scores n-1, a last 0) and how
  many gave each full order. Each lists people's own options with their backers, and the comments.
  Every question carries `passed` (`{by?, reason?}`; `by` with `digestNames`, and always for a
  person it is `for`) and `silent` (active guests with no signal); one `for` named people adds
  `for` and `missing`, by name. A `gathered` answer carries `endorsedBy`, the 👍 and ❤️ givers:
  names with `digestNames`, else a count; on a question with options it carries `picked`, the
  label of the option the person chose, and its `text` is their comment, which may be empty.
- **Presence.** The heartbeat (`schema/wire.schema.json`) carries `visible`, `lastInput` (seconds
  since the last key, pointer or touch), `lastFocus` (seconds since the tab last gained focus or
  was shown), `away` (the person's own snooze, sent until their next input), and `tab`, an id each
  browser tab keeps for its life (in `sessionStorage`). The server
  keeps a beat per tab, at most 8 per person, the least recent dropped. A tab is live until 90 s
  without a beat; a person with no live tab is offline. A tab is Away while hidden, after 5 minutes
  visible with no input, or snoozed; the person is Active while any live tab is Active, and Away,
  `since` the last tab went Away, only when every live tab is. Their question and typing come
  from a visible live tab before a hidden one and, within each, the one focused or shown most
  recently (the server's receive time less `lastFocus`, estimated once per `focusId`, which the
  page changes with each focus or show, so a late beat never moves it later), else, when no live tab sends one, from
  their latest beat; typing flags last 5 s. Each tab's beats have their own one-a-second
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
| `/api/proposal/all` | `{ids}` | Approve all in Proposed: each listed proposal, the new ones the owner's confirm counted, becomes a question in the next round as Make it a question makes one, and its author is told. All or none: one no longer new is 409 `wrong-status`, more than the round has room for 409 `round-full` (with `room`), so a proposal that arrived after the confirm stays in New |
| `/api/claude-proposal/act` | `{id, action: approve\|dismiss}` | Carries out or dismisses one of [Claude's merge and admit proposals](#claudes-merge-and-admit-proposals) (409 `wrong-status` once answered) |
| `/api/person/merge` | `{from, to}` | `from`'s answers, votes, reactions, chat, requests, uploads and problem reports move to `to`, every mention of `from` names `to`, and `from` goes. Into the owner, `from`'s secrets end instead of moving: that browser's next request gets 401 `merged-into-owner` (remembered until the server restarts), and its page asks for the owner link instead of joining again |
| `/api/decision/keep` | `{qid}` | Keeps a possibly reopened decision ([Answering](#answering), "Possibly reopened") |
| `/api/report/act` | `{id, action: seen\|resolved\|ask}` | Marks a problem report seen or resolved (409 `wrong-status` once resolved, or when it already is); either tells the reporter in a `report` notification. A resolved report leaves the owner's snapshot. `ask` sets `asked` on an open or seen report and writes `report-filed` for Claude (409 `wrong-status` on one that is resolved or already asked) |
| `GET /api/report/image?id=[&pic=P\|&add=N]` | | One report's first screenshot, its `P`th sent with it (`P` 1 to 4), or its Nth addition's (`N` 1 to 999); else, or with both, 400 `bad-field`. As `{id, image}`, a data: URL |

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
requests; the server stores each name of a person who is in as `<@pid>` (`session.tokenize`, longest
name first) and notifies that person once. The page sends the "@Name" it shows the same way, so a
masked name still reaches its person. Every page turns `<@pid>` back into "@Name" as it shows that
person's name now: masked like every name, a removed person's last name (the snapshot's
`mentions`), "@someone" for anyone else. Edit, Copy, Reply, Ask Claude and Propose take that
"@Name" text, never a token. A token counts toward the text limit, and a cut (a reply's excerpt, a
notification's body) never splits one. A rename shows in every mention of the person; a merge
points the merged person's mentions at the kept one. Claude never reads a token: every event in
the log, and a guest's own Claude through `/api/mine/requests`, gets "@Name", or "@someone" where
`digestNames` is off (for a guest's own Claude, where names are masked to that guest).

**Decision history.** `decisions` in `state.json` is an append-only log, oldest first, of each
lock (with its text), change to the locked text (`lock-change`, with the answer when it only
rewords it), `unlock`, `poll-close`,
`poll-reopen`, late Disagree with the locked answer (`late-disagree`, with the answer and reason),
the last of them taken back (`withdrawn`) and Keep decision (`kept`), each with when, the question and who. A question's decision is possibly
reopened while `late-disagree` entries follow its last other entry. Only the owner reads it, in the
owner's snapshot as `decisions`: a History fold under each question and Decisions in Help (More on
a phone). A session saved before the log starts with none.

There is no device or address blocking (C35): Remove stops a person's secret, and Approve new joins
or a new guest link stops a removed person rejoining under a new name.

## Claude's merge and admit proposals

Claude proposes; only the owner's tap merges or lets anyone in. When someone joins and waits under Approve new joins,
or joins under the name of someone already in who is not here now (less the " 2" a taken name gets; never the owner),
the server writes `person-joined` (`person`, `waiting`, the `device` and `browser` the join named, `sameName` with each
match's `pid`, `device` and `lastSeen` while the server remembers them, and names only with `digestNames`). Claude may
answer with `propose-merge` or `propose-admit`, which the owner sees in the Host view and the Inbox's Needs you, with
the reasons in words, Claude's note, and for a merge a reminder that the earlier person's own link (Use on another
device) avoids the duplicate next time. No address or location is kept or offered as a reason.

A proposal (`claudeProposals` in `state.json`, ids `K<N>`, the owner's snapshot only) keeps each person's name as Claude
saw it. Approve merges `from` into `to` as `/api/person/merge` does (that browser carries on as `to`, who gets a `merge`
notification) or lets the person in as Let in does; a waiting duplicate is let in first, as the owner's Merge requires.
While a person in it is renamed, removed, merged, let in, turned away, made a leader or trusted, it is out of the
owner's lists, and an approve then marks it `stale` and is refused (409 `stale`), merging no one. A person's own claim
to be someone is never a reason: that is their merge request to the owner. Dismiss marks it `dismissed`, and Claude cannot propose that pair, or that admit, again.

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
- **Versions.** A variant may name the variant it revises on an earlier prototype question,
  `previous: {qid, variant}` (400 `bad-field` when that is not a variant of an earlier prototype
  question, or another variant already revises it), so one prototype's versions form one line,
  the newest current. The question card lists each line as `v<n> · <qid> · <label>`, each version
  opening its own page, the current one marked, with a link that shows another version beside the
  current one. The page lists them too; Side by side (`#with=<qid>.<variant>`) shows the older of
  two beside the newer, framed with the same sandbox and no pin helper, so it takes no notes and
  nothing it posts is read, and dropped if it leaves its page. Notes stay on the version they were
  pinned to. The toolbar's Prototypes filter lists every round's prototype questions and opens the
  rounds that hold them.
- **Owner token.** Links to session pages (`Core.pageLink`) never hold it. The page keeps it in
  the tab's `sessionStorage`, takes it out of the address bar, and uses it again only on a reload
  or Back in that tab; when the owner follows a session link, `core.js` opens the page with
  `#owner=` in its fragment (a new tab with `noopener`), and that page takes it out in turn.

## Inbox

The top bar's Inbox opens a page of its own in the session's place below the top bar, for everyone, at every width;
Back to the session or Escape closes it, and every row opens where it happened and closes it. Its tabs, each behind
filter chips by status or kind that the device remembers, like the tab:

- Needs you: what needs this person now. Everyone sees the answers to their requests they have not opened and the
  questions they are asked to answer; a leader adds proposals and suggestions to place and a round to mark ready; the
  owner adds requests to run, answers to share, requests Claude failed (until opened), files offered, pictures to
  approve, open problem reports not yet asked about, merge and join requests, Claude's merge and admit proposals, a round
  marked ready, and decisions a late Disagree may have reopened, with Run, Share, Approve, Keep decision, Unlock and the
  rest on the rows. Only the owner's actions do anything: the server refuses them from anyone
  else.
- My requests: this person's requests that wait, run or have news, with the status they see: `waiting`, `running`,
  `answered` (an answer only its asker and the owner see), `unshared` (shown as "Answered, waiting for the host to
  share"), `shared`, `declined` or `failed`.
- Notifications: every notification, newest first, twenty at a time, by kind or unread only.
- History: what was handled: opened requests that are finished, and for the owner the other requests to Claude
  (running, shared, Just me, taken down, declined, discarded), reports seen or with Claude, and pictures done.

The snapshot's `inbox` carries a person's own requests and, for the owner, what waits on them (`run:`, `share:`,
`fail:` for a guest's request Claude failed, `report:` for an open report not yet asked about, `merge:`, `join:`, `people:` for a
proposal of Claude's, and `reopen:<qid>:<n>` for a possibly reopened decision, `n` the newest late Disagree's place in
the decision log),
built by `session.py` for the viewer alone (never another person's request or a result its requester cannot see).
`inboxSeen` in `state.json` keeps, per person, the status each item had when they opened it; an item whose status
moved since is unread, and only `POST /api/inbox/read {keys}` (keys of the caller's own Inbox; others mark nothing)
marks one read; Mark all read leaves `fail:` items alone, which clear only from their row. The badge leaves out the `request` notification kind, which the items already show. The owner gets
no `queue` line for what its Inbox lists as waiting (requests, shares, reports, merges, joins, Claude's proposals); queue lines for
proposals, suggestions and upload offers still count. The owner's own requests skip the queue: one starts running
when sent. A guest's request, the owner's guest identity included, still waits for Run.

The owner's pop-ups are for a join, a request waiting for Run and a problem report alone (`HOST_URGENT` in
`web/app.js`); everything else reaches the owner in the Inbox only. The Pop-ups switches at the top of the owner's
Notifications tab turn each kind of item waiting on the owner (also answers to share, merge requests and requests
Claude failed) on or off, kept as the owner's `popups` pref (`session.py` POPUP_KINDS). A guest's switches cover
Claude answered my request, named or mentioned, and a new round, kept as their own `popups` pref; until they change
them, the guest has the ones the owner turns on under Guests start with in the same tab (the `guestPopups` setting,
all three when unset).
Pop-ups that arrive while one shows become one with a count and Open Inbox ("3 requests wait on you"), and an item
that stops waiting drops out of it. Such a pop-up stays until it is closed or opened, or nothing in it waits any more;
every other toast goes after a few seconds.

## Discussion

Each question has a Discussion under its Claude section, folded by default; its head counts the
comments and those new to the viewer. `state.json` keeps `discussions` (qid -> comments) and
`discussionSeen` (pid -> qid -> the newest comment time they saw when they last opened it); others'
comments after that mark are new. Routes, each one write a second per person and route, and each
writing nothing when nothing would change:

| Route | Body | Who and what |
|---|---|---|
| `/api/discussion` | `{qid, text, attachments?}` | Anyone who may write. "@Claude" in the text also files an ask request with it (`request` on the comment), owner-gated like any guest request; the owner's own runs at once. It shares `/api/request`'s one a second. Too soon after a request, or with too many requests waiting, the comment still posts, with `requestRefused` and no request. A person keeps at most 30 comments on a question (hidden ones count); a question at most 200 and the session at most 2000 that everyone sees. People already in that Discussion get a rolled-up `discussion` notification; a mention notifies as usual. Posting marks the Discussion read for its author only when no one else's comment is unread to them |
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
message whose request is refused still posts with `requestRefused`; a filed one keeps the message's id as the
request's `msg`. Chat has no edit, delete or hide, so nothing
else applies. `request-run` lists it with `scope: "session"` and no `qid` or `question`, plus `from: "chat"` when a
message asked; the `result` op answers it with no `qid`, and its result is kept under `results.session` with no
`qid`, so a file from before loads as it is. Once shared, the result is also Claude's
chat message: the host's, marked `claude: {result}`, replying to the asking message while chat keeps it; the
result's `msg` names it. With chat off it is not posted, and stays in Ask Claude. A reply to it carries
`replyTo.claude`, so its quote reads Claude's wherever the page reads it. Reactions and replies to it tell no one,
and it cannot become a proposal. The Inbox, its
toasts and the Run cards say General, or "about the session", where they name a question; the owner shares it from
Ask Claude on "About the whole session", which lists those answers. A digest result carries `scope: "session"` in
place of `qid`.

## Sharing Claude's answers

A request names who sees its answer: `audience` on `POST /api/request`, `everyone` (the default) or
`me` ("Just me", kept on the request as `audience: "me"`; refused with `runner: "self"`, whose answer
already waits for the owner). Ask Claude defaults to Everyone on a question and to Just me about the
whole session; "@Claude" in chat or a Discussion always asks for everyone.

- **When it arrives.** Only `ask` and `research` answers skip the owner, and only while their asker
  is still in: an `explore`, `design` or `prototype` answer (which reads the linked project), or one
  whose asker was removed, waits for the owner's Share. Asked for everyone, such an answer is shared at once (on its question, or
  into chat for a general ask). Asked Just me, it is `private`: only its asker and the owner see it,
  and it stays out of the digest. Either way the asker hears it is done. A result no request asked
  for, and a guest's own Claude's, still waits for the owner's Share.
- **Review.** The `reviewAnswers` setting (Host settings, "Review Claude's answers before they are
  shared") holds every answer to a guest's request for the owner's Share, as sessions did before
  it; the owner's Share of a held Just me answer sends it to its asker alone. A new session writes
  it off; a state file from before it lacks it and so reviews, so a running session never changes
  under its people. The owner's own requests need no review.
- **Share later.** `POST /api/result/share {id}` shares an unshared answer with everyone: its asker
  their own `private` one (one a second), the owner any. Another person's answer, or one they cannot see,
  reads 404 `not-found`; a taken-down answer or a guest's own Claude's is the owner's to share (403
  `host-only`).
- **Take down.** The owner's `/api/request/act {action: "takedown", id}` unshares any shared answer:
  it becomes `private` with `takenDown {at}`, and its asker hears it. Its chat message stays as
  Claude's with `claude: {takenDown: true}` and the text "Taken down by the host.", as does every
  chat quote of it, and each is touched so open pages read it again; the owner's Share puts the
  answer back in that message. Only the owner shares it again; Discard is refused (409
  `wrong-status`) on a `private` answer, which its asker already has. A digest already sent keeps
  what it listed.
- **Move.** `/api/request/act {action: "move", id, qid}` (or `scope: "session"` for the whole
  session) puts a request and its result on another question, one a second. Only its asker or the
  owner moves it; anyone else reads 404 `no-such-request`, and every other action stays the owner's
  (403 `owner-only`). An unknown question reads 404, the place it is already 409 `same-place`, a
  running request 409 `wrong-status`, and a request on the asker's own Claude stays on a question.
  Once the host has taken up a request on the host's Claude (any status but `pending`), only the
  owner moves it (409 `taken-up`); a waiting one its asker moves reads unread again in the owner's
  Inbox. A result any answer cites stays put (409 `cited`). A shared result its asker moves waits for the
  owner's Share again; one the owner moves stays shared, and on the whole session it becomes
  Claude's chat message, as a Share makes it.

## Connect your Claude

A guest can run a request on their own Claude instead of the host's (R2-12; Brief C18-C20): in
Ask Claude, "Run it on my own Claude" sends `POST /api/request` with `runner: "self"`. Such a
request never enters the owner's queue, never makes an event or a notification (a mention in it
tells nobody), and is read, claimed, answered or failed only by its requester, with their secret
or their watcher key, through `GET /api/mine/requests[?status=]` and
`POST /api/mine/requests/{claim,result,fail}` (another person gets 404 `no-such-request`; one
write a second per route). Its result, marked `by: guest-claude`, waits for the owner's Share
whatever the review setting: until then only the requester ("Only you and the host see this until the
host shares it") and the owner see it. The owner can also take a shared one down (`takedown`, or
`discard` to drop it);
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

Off until the owner turns on Uploads (`shared_session.uploads`). Every place people write (the answer
box, Ask Claude, a question's ask box, a suggestion, chat, the Discussion and Propose) then has an
Attach button that offers "Upload a file" and lists the person's files the owner accepted. Every
picture (PNG, JPEG, WebP or GIF), picked or pasted into any of those fields, is redrawn in the browser
at most 1600 px and 512 KB, so no metadata such as EXIF or GPS leaves the device, then offered as a
file. A pasted one shows as a thumbnail chip, never as text in the field; it reads "Waiting for the
host" until the owner accepts it, and taking it off the form withdraws it (or removes it once
received). Each question keeps its own unsent chips. Send waits while a file is waiting for the
host, and takes off, naming it, a file declined, withdrawn, failed or removed meanwhile; a sent form
drops only the chips it sent. While Uploads is off no upload control shows and a pasted picture adds
nothing.

What carries files (C44, at most four, each an upload of the writer's own the owner accepted, each
once): `attachments` on `POST /api/answer` and `POST /api/pick` replaces the list, left out it is
kept. On `POST /api/answer`, empty `text` with `attachments` saves a picture-only answer, shown and
voted on like any other and listed in the digest with its `attachments` (so are a lock of it,
and a late vote, back, reaction or Disagree on it); changing an answer's files after votes marks it
edited after votes, as a text change does; empty `text` with
`attachments` left out or empty clears the answer, and so does declining or removing the last file
of an answer with no text or pick, unless its question is locked or its round went to Claude. On `/api/chat`, `/api/request`, `/api/suggest`, `/api/propose` and `/api/discussion` it is
optional and refused (403 `uploads-off`) while Uploads is off, and on `/api/request` with `runner:
self` (400 `bad-field`). A request filed by "@Claude" in chat or a comment carries that message's
files, a proposal forwarded from chat its message's, and `request-run` lists a request's
`attachments`, and a proposal placed as a suggestion keeps its proposal's. Declining or withdrawing a
file takes it off everything that carries it, and so does `remove` (`POST /api/upload/act`, the
owner's or the uploader's, on a received file): its status becomes `removed` (`at`, `by`), its
file is deleted, and `upload-removed` (`upload`, `file`) tells Claude never to read it again. A file
arriving, approved or ended touches the chat messages carrying it (`chatTouched`), so a page holding
older messages reads them again.

1. `POST /api/upload/offer` `{file, size, type, qid?, thumb?, avatar?}` (96 KB) records the offer; the file
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

The files sit in the private data folder, named by the server (`uploads/pending/<32 hex>`, then
`uploads/accepted/<yyyymmdd>-<upload id>.<ext>`); the person's file name is display text only. The
snapshot never carries a path: `myUploads` (one's own), `uploads` (the owner's, with a picture's
preview) and `files` (name, kind, size and status of the files on what that viewer reads: shown
answers, chat, comments and suggestions, plus their own hidden answers and comments, the proposals
they see and their own requests, every one for the owner). A file shows only where what carries it
shows, so a Just me request's, a proposal's or a hidden comment's never reaches another guest. The
snapshot's `files` covers the chat window only; `GET /api/chat` answers each page with the `files`
its messages carry.

Only a received picture is read back: done, of kind PNG, JPEG, JPG, WebP or GIF (never SVG or HTML),
and at most 512 KB (what the page makes of one); a larger file shows as a file. A guest's reaches
anyone but its uploader and the owner only once the owner approves the bytes that arrived:
`POST /api/upload/act {id, action: "approve"}` (owner only) sets the upload's `shown`, and the Host
queue lists each received guest picture waiting for it, showing the picture itself, with Approve
picture and Remove. The owner's own pictures need no approval. `myUploads` and `uploads` mark a
received picture `image` (and `shown` once approved); `files` marks it `image` once others may see
it, else `awaitsHost`, where the page shows "Waiting for the host" in its place.
`GET /api/upload/image?id=` (auth class person) answers its uploader, the owner, and, once approved,
whoever reads something that carries it, with `{id, image}`, a data: URL whose type comes from the
bytes' magic number, under the usual JSON headers (`nosniff`); every other id is 404 `not-found`,
and past 120 reads a minute per person 429 `slow-down`. It decides from a list kept per `rev`, never
by building a snapshot. The page shows the picture as a tile that opens the viewer and keeps the 24
it used last; the page policy's `img-src 'self' data:` is unchanged. Claude reads an upload only
through the Read-only `upload-reader` agent. Each start deletes pending files no upload names, declines files still
on their way from someone no longer in the session, and cuts a partial file back to the pieces its
record counts. A state whose upload id, extension or received name is not one the server makes
does not load.

### Profile pictures

A person may show a profile picture on their avatar in place of their initials. They pick it on
their own person card (Your picture: Choose a picture, Replace picture, Remove picture); the
browser redraws the middle square at 256 px at most, as WebP where it writes it, else JPEG, and
offers it with `avatar: true` through the upload path above, so the first piece's magic-number
check applies. It needs no accept: it is small, and others see it only once approved. A guest's
follows the Uploads switch (403 `uploads-off`, "The host has pictures off in this session."); the
owner's own does not. An avatar offer must name a PNG, JPEG or
WebP (415 `file-type`), be 256 KB at most (413 `upload-too-large`), and name no `qid`; no post may
carry it (409 `wrong-status`). Once it arrives it replaces the person's last one, which is removed
and deleted, and a new offer withdraws one still on its way. Neither event goes to Claude
(`upload-received` and `upload-removed` are left out for it). The person and the owner remove it with
`POST /api/upload/act {id, action: "remove"}`.

The owner's own picture shows at once; a guest's shows to others only once the owner approves it,
as any received picture (Approve picture on the guest's card or in the Host queue). Until then,
and after a replace until the new one is approved, everyone but its uploader and the owner sees
initials, `people[].avatar` (the upload id) is left out, and `GET /api/upload/image` answers them
404. While names are hidden (Show names off), the snapshot of a guest leaves `avatar` out, the image
read answers them 404, and every page shows initials. `myUploads` and `uploads` mark the upload
`avatar`. The page reads each picture once and shows it as a circle crop over the initials.

## Problem reports

Anyone joined can report a problem: "Report a problem" in the phone More sheet and the desktop Help
popover, and "Report this" on the toast of an action the server refused. The form asks "What went
wrong?" (required, 2000 characters) and takes up to four optional screenshots (`accept` png, jpeg or
webp, `multiple`, no `capture`), picked several at once, pasted or added one by one, each of which the
browser re-encodes to at most 1600 px on its long edge and 512 KB. Before
Send it lists, under "Sent with this report", every field that goes with it: the view and phone
tab, the question and round, the device kind and browser family, `innerWidth` x `innerHeight` and
the visual viewport's width, height and scale, the build, and the last 5 errors the page saw,
refusals included ([Logs](#logs)). Never an answer, chat, the address or its fragment, or a credential.

`POST /api/report {text, ctx, images?}` (auth class person) takes them, `images` a list of at most
`MAX_REPORT_IMAGES` (4) data: URLs, each of whose bytes must start as PNG, JPEG or WebP do (415
`file-type`; over 512 KB 413 `upload-too-large`; a fifth, or `image` beside `images`, 400 `bad-field`).
One picture may still come as `image`. Its body cap is `REPORT_SEND_MAX` (about 2.8 MB) instead of
32 KB. A report is allowed while Uploads is off: its pictures, checked, saved in the private data
folder, the first as `reports/<id>.<png|jpg|webp>` and picture n after it as `reports/<id>-p<n>.<ext>`,
and shown to the owner alone; every other upload stays refused (403 `uploads-off`). One report per
person every 10 s (429 `slow-down`), 5 open per person (429 `too-many-pending`), 500 per session
(429 `too-many-reports`). The record, `reports` in `state.json` (`{F<N>: {by, text, ctx, image?,
moreImages?, status: open|seen|resolved, asked?, adds?, ts}}`, `moreImages` the second to fourth pictures; each
optional, so a file from before loads), reaches only the owner's snapshot (`reports`, with `image: true` and
`images`, the count, instead of the paths) and shows in the Host queue as a Problem, with one Show screenshot per
picture that loads it, Seen, Resolved and Ask Claude about this report ([Moderation](#moderation)).

**Your reports.** The reporter's own snapshot carries `myReports` (`{id, text, status, ts, image, images, adds}`, never the
context or a path), which More and Help list as "Your reports" with `open` read as Sent, `seen` as Seen by the host
and `resolved` as Fixed. While a report is not resolved, its reporter adds a line, a screenshot or both:
`POST /api/report/add {id, text?, image?}` (auth class person; one picture, the picture checks of `/api/report` and a
body cap of `REPORT_MAX`, about 732 KB; one
a second; at most 10 per report, then 409 `too-many`; 409 `wrong-status` once resolved; anyone else's report is 404
`not-found`). Each lands in the report's `adds` (`{text?, image?, ts}`, a picture saved as `reports/<id>-<n>.<ext>`),
which the owner's Problem item lists. A seen report goes back to `open`, so it waits on the owner again, unless
the reporter already has 5 open (429 `too-many-pending`). An addition clears `asked`, so the owner can ask Claude again. A report alone
never reaches Claude: only the owner's Ask writes `report-filed` (`report`, `qid`, `text`, `images`, how many pictures came with it, and `adds`, the text the reporter added, and `addImages`, how many pictures they added; never a path), as
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
| `summary-batch` | INFO | `summaries dropped counts data`: every `summary` taken since the last batch, written every 10 minutes and when the server stops, if there was one and it came from at least 2 guests or only the owner, or at shutdown of a session only one guest sent summaries to (counts only, see below). `counts` is a JSON object of the summaries' `use:`, `rage:` and `dead:` counts added up; `data` is a JSON array of `[message, device]` pairs, the rest of each summary, sorted; both in ASCII with each space as `\u0020`. `dropped` counts summaries past the batch's 100,000 bytes, and at shutdown those from a single guest, or a one-guest session's pairs (see below). No pid, and no time but the batch's |

```text
2026-10-17 13:21:56,794 WARNING request method=POST route=/api/person/role status=400 ms=0.5 pid=host code=bad-field field=role message="role must be one of leader, guest."
2026-10-17 13:21:57,102 ERROR request method=POST route=/api/rename status=500 ms=1.2 pid=pidAnn001 code=state-invalid message="The server could not do that; nothing was written." trace="Traceback (most recent call last):\x0a  File \x22...\x22 ..."
2026-10-17 13:21:58,330 WARNING client pid=pidAnn001 kind=error message="TypeError: x is undefined" source=/app.js:12 route=/ ua="chrome computer" fp=1a2b3c4d
2026-10-17 13:30:00,412 INFO summary-batch summaries=2 dropped=0 counts={"dead:vf-pencil":1,"use:vf-vote":5} data=[["pv=0a1b2c3d\u0020lat:/api/vote=0,3,1\u0020rb:/api/vote=1\u0020gap=900\u0020inp=184:pointer:vf-vote\u0020lcp=1200:vf-qtext","phone"],["pv=5e6f7a8b\u0020gap=400","computer"]]
```

A pid is no credential. No entry holds a token, secret, guest key, owner link, request body, answer
or chat text, or upload.

**What the page records** (`web/core.js` telemetry). Faults go out at once, under the person's pid
so they can be matched to that person's request entries, the first time each fingerprint (`fp`)
shows; a repeat is not sent:

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
page showing again to its first good poll; `use:<control>` taps, `rage:<control>`
rage taps (the third tap on one control within a second of the first) and `dead:<control>` dead taps (a tap
after which the page changes nothing, no DOM change and no scroll, for a second; never a link that opens
elsewhere), counted on a person's taps on buttons, `input` buttons, links, `role=button` and `summary`, a
disabled control getting no tap; `inp` (ms, interaction type,
component) and `lcp` (ms, component) from the vendored web-vitals build, the component `-` where
web-vitals names its target by a selector or an id instead (an element gone before it measured), or `inp=missing`,
`lcp=missing`, `vitals=missing` where the browser API or the file is missing. What does not fit in
500 characters waits for the next summary. Nothing is sampled. A control is named by its first `vf-` or
`core-` class (letters and hyphens) that is not a style class such as `vf-btn`, on it or its nearest
ancestor, never by its text, label or id.

The server keeps only the device word of a summary's `ua` (`phone`, `tablet` or `computer`, else
`unknown`) and lifts every `use:`, `rage:` and `dead:` token out of the summary into the batch's
`counts`, dropping one not shaped like a `vf-`/`core-` class name and every `rep:` token an older page
sends, whose fingerprint is on a fault entry that names the person. A batch is written only once at
least 2 guests sent summaries to it (or only the owner did): with fewer it waits for the next batch,
and at shutdown its summaries are only counted as `dropped`. So no pair holds a fingerprint or a
browser that would match it to a fault entry's pid, and in a session with two or more guests no
batch's counts are one guest's.

A one-on-one session (only one guest ever sent a summary) would otherwise record nothing, so its
held batch is written at shutdown with its `counts` only, the session's totals, and its pairs, each
one page view's record, counted as `dropped`. In one on one the host knows who the guest is, so
these totals are that guest's: what keeps them unlinked is that they carry no pid, fingerprint,
browser or page view, and no time but the session's end. A one-guest session's counts are kept
only while its held batch is under 100,000 bytes, pairs included; past that a summary is dropped
whole, and a crash or `share.sh stop` on Windows (below) loses them all.

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
device with the count of page views missing the API, taps, rage taps and dead taps by control
(`features`), and how many summaries came in how many
batches from how many page views, and how many were dropped.
The owner's own page views stay out of the timings. A summary counts at its batch's time, for
`--since`. A `rep:<fp>` count in an older log still adds to its fingerprint's count. `logs --errors` leaves batches out.

## Themes

The page's theme is a mode, an accent and a palette. The owner sets the default for everyone in
Session settings ("Default theme for everyone", the `theme` setting); each person can choose their
own in their card ("Theme, just for you", the `theme`, `accent` and `palette` prefs), which wins on
their own page.

| Part | Values | Default |
|---|---|---|
| `mode` | `system` (follows the device), `light`, `dark` | `system` |
| `accent` | `teal`, `indigo`, `violet`, `amber` | `teal` |
| `palette` | `default`, `midnight`, `slate`, `paper`, `contrast` (High contrast) | `default` |

Each palette has a light and a dark variant, chosen by the mode, and sets the whole page's surfaces
and text. The accent applies over every palette except High contrast, which uses its own accent; with
High contrast chosen for yourself, your accent swatches are disabled and say so. The owner's default
accent stays settable, since it still reaches anyone who picks another palette. `palette` is optional
in the `theme` setting: a session written before palettes has none, loads as it was, and shows the
default palette until the owner, or a person for themselves, picks one.

## Read aloud and dictation

Two switches in a person's own card, each off until they turn it on and kept with their other preferences (the
`readAloud` and `dictate` prefs). Both use the browser's own Web Speech API; the page makes no request of its own for
them and the CSP is unchanged.

- **Read questions aloud** adds a speaker button to the question's row. It speaks the question, then each option label
  the person's page shows, read from the page itself, so nothing hidden from them is spoken. A second press or Escape
  stops it, and so does moving to another question. A voice on the device is used when the browser lists one for the
  page's language.
- **Dictate answers and comments** adds a microphone button to the answer box and the Discussion comment box. The words
  land at the box's caret for the person to edit, and nothing is sent until they send it. A second press or Escape stops
  listening. The switch and the buttons show only where the browser has `SpeechRecognition`.
- Recognition may run on a server: Chrome's has by default. Where the browser offers on-device recognition
  (`processLocally`), a press asks for it first; a device without the language falls back at once to the browser's
  service. Until words have been heard on the device, the card shows under the switch: "Your browser may send what you
  say to its maker's speech service to turn it into text." The page never calls `SpeechRecognition.available()`, which
  ends the page's process in a Chromium build without Chrome's handler for it, and never installs a language pack.

## Data contract

One folder per session: `<memory_dir>/<topic-slug>/shared/<session-slug>/`.

| Path | Writer | Mode | Holds |
|---|---|---|---|
| `state.json` | server | 0600 | The session (`schema/state.schema.json`) |
| `defaults.json` | the skill | | Settings for a new session; `guestPort`, `adoptTunnel` to adopt a running cloudflared |
| `ops.json` | Claude | | One apply; deleted when it lands |
| `.shared-secrets.json` | server (made on first start) | 0600 | The control token, the owner token and `ownerAt`, when the owner token was issued |
| `.owner-link` | server | 0600 | `http://127.0.0.1:<guest port>/#owner=<token>` |
| `.owner-open-<hex>.html` | `share.py ensure-running --open` | 0600 | A page that sends the browser to the owner link; deleted 30 s later |
| `staging/` | server (made at every start) | 0700 | Captures Claude saves for `add-asset` |
| `.shared-session.json`, `.shared-session.env` | session-bridge `start` | 0600 | Control port, pid, control token, nonce |
| `.shared-ports.json` | server | 0600 | The guest and control ports, reused on every start |
| `.shared-tunnel.json` | `tunnel.py` | 0600 | `{pid, url, port, startedAt, marker, processStart, adopted}`, plus `hostname` and `tokenFile` (the path, never the token) for a named tunnel and `retired` (`{pid, url, marker, processStart, adopted, until}`) after a switch |
| `cloudflared.log` | cloudflared | 0600 | Its output, where a quick tunnel's address and a named tunnel's first connection are read |
| `server.log` (+ `.1`..`.3`) | server | 0600 | One entry per request and per page error report ([Logs](#logs)); rotated at 1 MB, 3 kept |
| `.shared-server.err` | the server's stderr | 0600 | Why a start failed |
| `.shared-reported` | `share.py` | 0600 | The guest link the last `ensure-running` printed (for `shareChanged`) |
| `.watch-seq`, `.watch-replay` | `watch.sh` | | |
| `assets/<16 hex>.<ext>`, `assets/.<id>.json` | server (`add-asset`) | | The file, and its kind, size and scale |
| `uploads/pending/<32 hex>`, `uploads/accepted/<yyyymmdd>-<upload id>.<ext>` | server | 0700 folders, 0600 files | An accepted upload's pieces so far; a received one (see [Uploads](#uploads)). Only a received picture is read back, as a data: URL from `GET /api/upload/image` |
| `reports/<report id>[-p<n>\|-<n>].<png\|jpg\|webp>` | server | 0700 folder, 0600 files | A problem report's screenshot, with `-p<n>` the nth sent with it, and with `-<n>` the reporter's nth added one ([Problem reports](#problem-reports)); only the owner's `GET /api/report/image` reads one back, and Claude reads one only through the Read-only `upload-reader` agent |

Every `GET /api/state` with identity carries `rev` and `build` (a hash of the served web files);
every answer carries `X-Shared-Build`. A page built for another build reloads itself. Its `ETag` moves with `rev`, presence and a 5-second clock tick (so an
offline or away person shows without a write); a heartbeat that changes nothing anyone sees moves
nothing. A poll whose `If-None-Match` differs only in presence or the tick gets `{rev,
presenceOnly: true, serverTime, presence, lastSeen}` (`wire.schema.json` `presenceOnly`), and the
page keeps the rest of its last snapshot.

## Security model

- **Two listeners, both 127.0.0.1.** Only the guest listener is the tunnel's target. The control
  listener (ops, the watcher's long-poll, status) is never tunneled and needs `X-Shared-Token`.
- **Host and Origin.** The guest listener serves `Host` `127.0.0.1:<port>`, `localhost:<port>` and
  the current tunnel host only (DNS rebinding), and checks `Origin` when sent. A tunnel that
  restarts at a new address drops the old host. After a switch, the retired tunnel's host stays
  allowed while that tunnel runs, and `GET /api/state` there answers only `{moved: <new address>}`
  to anyone, identified or not: the old address's holders learn the new address, nothing else.
- **Identity is a header.** `X-Session-Secret` (a guest) or `X-Owner-Token` (the owner), never a
  body field or a URL query; a pid in a body is ignored. Owner routes need `X-Owner-Token`
  itself. `state.json` keeps only sha256 hashes. Custom headers force a CORS preflight that is
  never answered.
- **The host's other devices.** The owner's menu item Sign in on another device (`POST
  /api/owner/pair`) makes a one-time code: 8 characters from 31 (no 0, O, 1, I or L), about 39.6
  bits, shown typed as `XXXX-XXXX` and as a QR code of the guest link plus `#pair=<code>`, drawn
  in the page by its own encoder. Only its hash is kept, in memory; it works once, for 2 minutes,
  and a new code replaces it. `POST /api/owner/pair/redeem` (public) trades it for the device's own
  credential: one try a second per address, and an address with 5 wrong codes is refused the live
  code while every other address keeps it, so a stranger cannot burn it and a guesser gets 5 tries
  per address it holds (an IPv6 address counts by its /64) against 31^8. The join dialog's "Are you the host? Sign in with a code" link, under Join, takes
  a typed code. The device sends its credential as `X-Owner-Token` and acts as the owner; it keeps
  it in `localStorage` (`ownerDevice`) until signed out. `state.json` keeps its hash under
  `credentials.devices`, at most 10. Making a code and New owner link (`/api/link/owner`, which
  answers the new owner token) work only with the owner link's own token (403
  `host-device-only`), so the owner link never reaches another device. The owner's Signed-in
  devices list signs one out (`POST /api/owner/devices/revoke`) and the next request with its
  credential gets 401; signing out, closing the session or a new owner link also renews the asset-cookie key, so no
  cookie outlives it (every open page gets a new one on its next poll). A new owner link,
  including one issued at start, and closing the session sign out every device; reopening the
  session brings none back.
- **Joining.** A new session issues a guest key, so its first guest link already ends in
  `#join=<key>` and a join without the key gets 403 `bad-guest-key`. A session saved before
  sessions had one keeps an empty key, and with it a link that needs none, until the owner presses
  New guest link; nothing changes it on its own.
- **Assets.** `/assets/*` answers only a joined person or the owner: the identity headers, or the
  asset cookie every `/api/state` answer with identity sets, since an `<img>` or a frame sends no
  header. The cookie holds the pid, an expiry 15 minutes ahead and an HMAC under a key each server
  start makes (`HttpOnly`, `SameSite=Strict`, `Path=/assets/`, `Secure` through the tunnel, named
  for the guest port). Each poll renews it; a removed or waiting person's cookie reads nothing (403),
  and without either credential the answer is 401.
- **Requests.** JSON POSTs only (415), the 32 KB body cap checked before reading (413), and the
  whole body within 10 s (408; a problem report's, up to four pictures, within 60 s). A request other than a POST that carries a body
  (`Content-Length` above 0 or any `Transfer-Encoding`) gets 400 and its connection closes. A
  refused request (bad host, rate limit, body) answers once and runs nothing.
- **Limits.** All are constants at the top of `session.py`:

  | Limit | Value |
  |---|---|
  | Requests per address (`CF-Connecting-IP` only, never `X-Forwarded-For`; an IPv6 address counts by its /64) | 100 a second, bursts of 200; the 10000 most recently seen addresses are remembered |
  | Joins | 30 a minute per address and guest key; 60 per 10 minutes per guest key across all addresses (rotating the guest link starts a new count) |
  | Host sign-in codes | one made a second; one try a second per address; 5 wrong tries shut that address out of the live code; 10 signed-in devices |
  | Writes | 1 a second per person per route, on every route that writes (answer, pick, vote, react, disagree, go-with, rename, color, prefs, about-you, notifications/read, chat, propose, suggest, request, annotate, merge-request, report/add) |
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
- **What a visitor reads.** Without identity, `/api/state` is `{title, ended,
  joinNeedsKey}` only; a removed person and an owner link from before a rotation read nothing.
  An unshared result reaches only its asker (a Just me answer, one taken down, their own Claude's)
  and the owner.
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
| Owner token | `.shared-secrets.json` and `.owner-link` (0600); for 30 s after `--open`, the `.owner-open-<hex>.html` page (0600) the browser is handed, whose path, not the token, is on the opener's command line; the owner's browser (the link's fragment, never sent to the server, and its history; the tab's `sessionStorage` once a page took it out of the address bar); the transcript when the owner asks for `url --owner` |
| Sign-in code | The owner's screen while it lasts (2 minutes, once), the QR code's link fragment on the device that scans it, taken out of the address bar at once; the request body of `/api/owner/pair/redeem`, which Cloudflare's edge sees |
| Device credential | That device's `localStorage` (`ownerDevice`); the `X-Owner-Token` header it sends, which Cloudflare's edge sees. It acts as the owner, except for making codes and a new owner link |
| Guest secret | The guest's browser storage and personal link (`#me=` fragment, also the one a page opens when a tunnel switch moves it); the `X-Session-Secret` header, which Cloudflare's edge sees because the tunnel terminates TLS there |
| Tunnel token (named tunnel) | The file `tunnel_token_file` names, which only cloudflared reads (`--token-file`); its path, not the token, is on cloudflared's command line and in `.shared-tunnel.json` |
| Cloudflare API token | The owner's secret store, and `cfdns.py`'s `Authorization` header to Cloudflare's API; never on a command line or in its output |
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
node plugins/planning/shared/tests/ui_proto_versions.js
node plugins/planning/shared/tests/ui_connect.js
node plugins/planning/shared/tests/ui_uploads.js
node plugins/planning/shared/tests/ui_attach_paste.js
node plugins/planning/shared/tests/ui_report.js
node plugins/planning/shared/tests/ui_claude_proposals.js
node plugins/planning/shared/tests/ui_general.js
node plugins/planning/shared/tests/ui_advance.js
node plugins/planning/shared/tests/ui_askbox.js
node plugins/planning/shared/tests/ui_myreports.js
node plugins/planning/shared/tests/ui_welcome.js
node plugins/planning/shared/tests/ui_per_device.js
node plugins/planning/shared/tests/ui_review.js
node plugins/planning/shared/tests/ui_rail_header.js
node plugins/planning/shared/tests/ui_reopen.js
bash plugins/planning/shared/tests/align.test.sh
```

`ui_connect.js` checks Connect your Claude for a desktop guest and a 390x844 phone guest: the
watcher and Desktop chat links and their decoded prompts, Copy prompt, Paste answer, the answer
marked as the guest's own Claude and held for the owner's Share, a watcher's round trip with a
watcher key and its revoke, the owner taking a shared answer down, that the owner and another
guest never see the request and another key cannot answer it, and that on the phone every Connect
control lies inside the viewport. Before the browsers it checks the one-request prompt's data
block against look-alike end markers.

`ui_claude_proposals.js` checks Claude's merge proposal: a second Ann joins while the first is not here, the server
writes `person-joined`, Claude's `propose-merge` shows in the owner's Host view and Inbox with its reasons and the
own-link reminder, a guest sees none and a guest's approve is refused, nothing merges before the owner's Merge, and
Merge folds the phone into the earlier Ann with her chat.

`ui_advance.js` checks "Go to the next question after I answer" (the `autoAdvance` pref, off by default, in the
person's own settings): a single pick or a scale value with the comment box empty shows "Next question in 2 s · Stay"
and moves on; Stay cancels; a pick with a comment, pick-many, rank and a written answer never move on.

`ui_speech.js` checks Read aloud and Dictate with the page's speech APIs replaced by recording stubs: both switches off
by default and kept on the server, turning them on moves nothing, Read aloud speaks the question then its options and
never an answer the owner has not shared, a second press or Escape stops it, Dictate fills its box and sends nothing,
the disclosure and its on-device cases, and no Dictate switch or button without the API. `align.js` checks both
controls on in its `speech-choice` and `speech-answer` views.

`ui_askbox.js` checks the guest's one Ask Claude box: no Ask, Research or Explore picker in the panel or a question's
form, a "Use the web" chip, off by default, that sends the request as `research` (else `ask`), and the owner keeping
the picker.

`ui_review.js` checks sharing Claude's answers and the host's review view: Everyone on a question's Ask box and
Ask Claude, Just me about the whole session; an answer asked for everyone reaching another guest when it arrives, a
Just me one reaching only its asker until they share it; the Inbox page's Needs you listing requests newest first,
Run moving them to History, a failed row's reason and Run again, Take down hiding an answer from others, and the
chips and the Inbox tab kept over a reload.

`ui_inbox_page.js` checks the Inbox page: Needs you holding a request Claude failed until it is opened but never one
the owner discarded or cancelled, nor a report already asked about; History holding them; rows opening where they
happened and closing the page; a leader's proposals to place and the server refusing a leader's Run.

`ui_reopen.js` checks a late Disagree on a locked answer once its round closed: the owner's Possibly reopened row
with the locked answer, the reason, Keep decision and Unlock; a guest reading "Needs review: Q1 may be reopened" on
the dependent question with no row, History or Decisions; the owner's History under the question and Decisions
timeline; Keep decision clearing the row and badge, a newer Disagree raising it again, and Unlock.

`ui_rail_header.js` checks, at 1440x900 and on a 390x844 phone, that every round's label in the rail starts at one x,
with a check once something in the round is done and an empty ring before, both aria-hidden; that the phone's question
header keeps the arrows on the position's row and the host's Purpose and Ask someone (then Change who) together on one
row of 44 px targets, nothing past the screen, while the desktop header stays one row; and the owner's Approve all in
Proposed: a confirm naming how many, each counted proposal a question in the next round, one that arrived after the
confirm left in New, and no guest offered it.

`ui_myreports.js` checks Your reports on a 390x844 phone from More and on a desktop from Help: no entry before a
report, the list with Sent, Seen by the host and Fixed, a line and a screenshot added (the owner's Problem item shows
the line and reads the picture back at 1600 px), a seen report waiting again once added to, a fixed one taking no
more, and another guest never holding it.

`ui_welcome.js` checks the first-join welcome card: shown by default, its first line "Enter your name to join, then
answer this round's questions.", the goal and Start here; a visible Skip that closes it and the tour offer at once
(the `tour` pref says skipped); closed after a reload on that device (`localStorage`, per person); "Show the tour
again" in the person's settings bringing both back; a 44 px Skip on a 390x844 phone; on a return visit the goal in
one closable line, closed for the rest of that tab's visit (`sessionStorage`); About you (tech comfort and a note)
in the person's card, shown only on the owner's Host view; and in Instagram's in-app browser a banner to open the
page in Safari, with Copy link, that never blocks the page.

`ui_per_device.js` checks a question asked once per device (`answerScope: device`): the page sends the device kind
with the answer, a person who answered on a computer is asked on their phone for that phone too, and the owner reads
one card per device, each named with it.

`ui_uploads.js` checks uploads with a 390x844 phone guest and a desktop owner: no upload control
while Uploads is off, an offer held in the guest's browser, the owner's Accept, a chunked send
that resumes after a dropped piece and a reload, the file attached to a pick and shown to another
guest, and a declined file deleted from the browser and shown as "Not accepted".

`ui_attach_paste.js` checks attach and paste on desktop guests: with Uploads off a pasted picture adds nothing; a
Propose form opened before Uploads went on takes a paste, and taking that chip off withdraws it; on, the answer box,
Ask Claude, chat, the Discussion and Propose each show Attach, and a picture pasted into each becomes a thumbnail chip
reading "Waiting for the host" with the field's text left as typed; chat will not send before the owner's Accept;
received, another guest sees "Waiting for the host" until the owner's Approve picture in the Host queue, then a tile
on the chat message, the answer and the comment that opens in the viewer, while the proposal's, the request's and,
once hidden, the comment's stay from him. It also checks a Discussion chip staying on its own question, Send taking a
declined file off by name, a picked JPEG reaching the host redrawn without its EXIF, the owner's own paste, the
question's ask box and Suggest taking a paste, and the owner's Remove.

`ui_report.js` checks Report a problem with Uploads off: on a 390x844 phone from More, the sent
list before Send, a 3200x1800 screenshot re-encoded to 1600 px, three more picked at once and a fifth
refused, the field and Send report above a keyboard, and a request carrying four pictures and no
answer, chat, fragment or secret; the desktop owner's Problem item, each picture on its own Show screenshot, Ask Claude about this report (the owner's alone), Seen telling the reporter, and
Resolved; on a desktop, Help's entry and a
refused action's "Report this", whose form lists the refusal. `ui_layout.js` also sweeps the form
with keyboards at 320 to 430 px wide.

`ui_proto.js` checks the prototype page on a desktop and a 390x844 phone in separate browser
contexts: the preview tile and its link, the variant switcher, Annotate, a note pinned to an
element of an html variant and to a spot of a picture, the notes in the Claude thread and the
digest, the variant's sandbox, and a forged pin message being ignored. `ui_proto_versions.js` checks
a prototype revised in a later round: the Prototypes filter finding both rounds' prototypes without
scrolling, the later question's version list with the current version marked, opening version 1
from it, the two side by side on a desktop and stacked on a phone, and a note staying on its version.

`ui_contrast.js` checks WCAG 2.2 AA contrast on the main page states in every palette, in light
and dark: text and placeholders, field edges, icon-only buttons and the Propose button's edge; per
palette, mode and accent, the accent's text on every surface, text on the accent and the ten person
colors; and that a palette picked in Session settings or in a person's own card applies on the page.

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
poll carries a query string; no page breaks the CSP; and a returning guest comes back as the same
person, keeping its stored secret when its first heartbeats get a 429 or
no answer. `ui_formats.js` covers, in a session past its first round, `multi`, `scale` and `rank`
(keyboard, and touch on a 390x844 phone, whose Questions tab must take taps with two rounds
listed), Something else on `choice`, `multi` and `rank`, Disagree, the `down` reaction and a
diagram's alt text. `ui_presence.js` (about 4 minutes) hides a tab for 3 minutes with throttled
timers, closes another, snoozes a third, keeps one person in two tabs with one hidden, and checks
none of that gets a 429. The
browser suites share `browser_harness.js` (not a test), need playwright-core (from `node_modules`,
or the one playwright-cli bundles), and SKIP without it. `tracer.test.sh` runs the whole flow against the fake tunnel. `tracer-live.test.sh` uses a real
cloudflared (a path argument, else PATH), opens a public address, and SKIPs in CI or without one.
