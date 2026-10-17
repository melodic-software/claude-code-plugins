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
| `schema/*.schema.json` | The persisted and wire shapes: `state`, `ops`, `event`, `question-shape` |
| `web/` | The page, served from a fixed allowlist (`/`, `/core.js`, `/app.js`, `/core.css`, `/app.css`, `/proto.js`) |
| `tests/` | `test_session.py`, `test_server.py`, `test_share.py`, `test_tunnel.py`, `test_load.py`, `test_migrate.py`, `test_schema_shapes.py`, `tracer.test.sh`, `tracer-live.test.sh`, and `fixtures/` (incl. `fake-cloudflared.sh` and `fake_cloudflared.py`) |

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
| `status` | | `{ok, running, tunnel, guestUrl, round, people, queue, unhandled, lease}` |
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

```bash
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
| `open-round` | `questions` (1..8), `placements?` | Closes the `working` round (or starts round 1) and opens the next |
| `close-round` | `placements?`, `reason?` | `working` -> `closed`, no new round |
| `ack-round` | `round` | `sent` -> `working` |
| `result` | `qid`, `request?`, `kind`, `used`, `why`, `summary`, `sources`, `report` | Stores a result unpublished; the owner publishes or discards it |
| `fail-request` | `request`, `reason` | `running` -> `failed` |
| `add-reference`, `remove-reference` | `qid`, `reference` / `index` | |
| `add-asset` | `path`, `as?`, `scale?` | Copies a PNG, JPEG, WebP, SVG or HTML file (by its bytes, at most 10 MB) from the data folder, where captures go in `staging/`, into `assets/<16 hex>.<ext>`, named by its content; returns `{id, kind, bytes, at, scale}`. Usable from the next apply; a refused apply removes the files it copied and puts back any sidecar it rewrote |
| `make-question-from` | `proposal`, `question` | |
| `handle` | `seqs` | Marks events handled |

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
  | Writes | 1 a second per person per route, on every route that writes (answer, pick, vote, react, go-with, rename, color, prefs, about-you, notifications/read, chat, propose, suggest, request, annotate, merge-request) |
  | Heartbeat | 1 a second per person (429 otherwise) |
  | Stored chat, notes, suggestions | the newest 2000 messages; 2000 notes; 200 suggestions per question, with votes on a dropped one dropped too |
  | Connections served at once | 64; one more is answered 503 `busy` |

- **Headers.** Every answer, http.server's own refusals (414, 501 and the like) included:
  `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy: no-referrer`. HTML adds the page policy (`default-src 'self'` ...
  `frame-ancestors 'none'; base-uri 'none'; form-action 'none'`). `/assets/*` adds
  `Content-Disposition: inline` and `Content-Security-Policy: sandbox`; an HTML asset gets
  `sandbox allow-scripts; default-src 'none'; script-src 'unsafe-inline'; style-src
  'unsafe-inline'; img-src 'self' data:; font-src data:; connect-src 'none'`, never
  `allow-same-origin`.
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
| Owner token | `.shared-secrets.json` and `.owner-link` (0600); for an imported session, `state.v0.json` (0600) and the prototype's own state file; for 30 s after `--open`, the `.owner-open-<hex>.html` page (0600) the browser is handed, whose path, not the token, is on the opener's command line; the owner's browser (the link's fragment, never sent to the server, and its history); the transcript when the owner asks for `url --owner` |
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
```

`tracer.test.sh` runs the whole flow against the fake tunnel. `tracer-live.test.sh` uses a real
cloudflared (a path argument, else PATH), opens a public address, and SKIPs in CI or without one.
