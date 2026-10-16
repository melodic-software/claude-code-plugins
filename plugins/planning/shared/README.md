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
| `migrate.py` | `schemaVersion` migrations, pure `dict -> dict` |
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
| `ensure-running` | `[--open] [--defaults-file F] [--guest-port N]` | `{ok, guestUrl, localUrl, ownerLinkFile, shareChanged, resumed, tunnel, watch}`: starts or reuses the server and the tunnel. A new session's `state.json` comes from `defaults.json` (`{"settings": {...}}`, state.schema field names). `--guest-port` applies only when the session is created; later starts reuse the recorded ports |
| `stop` | `[--keep-tunnel]` | `{ok, stopped}`: ends the armed watcher, the server and cloudflared; keeps the ports and the state. `--keep-tunnel` keeps the guest link for the next start |
| `restart` | | Stops and starts the server only, on the same ports, with the same control token: the tunnel, the guest link, the state and an armed watcher all survive. Open pages see the new build and reload |
| `status` | | `{ok, running, tunnel, guestUrl, round, people, queue, unhandled, lease}` |
| `url` | `[--owner]` | `{guestUrl}`, or `{ownerUrl}` (a credential, printed only on request) |
| `list` | `--root '<memory_dir>'` (no `--dir`) | `{sessions: [{dir, title, running, guestUrl, round, ended}]}` |
| `apply` | `--file F` | `{ok, results}`; deletes `F` once it applies. A missing `F` is a no-op, so `wake.sh` re-arms with nothing to write |
| `lease` | `[--release]` | `{lease}` |

Exit codes: 0 done; 1 refused (bad arguments, a state file from a newer version, a failed
migration, a `--guest-port` on an existing session); 2 a prerequisite is missing (Python 3, curl,
cloudflared) or the server cannot start or be reached; 3 no tunnel address in time (the server
keeps running on `localUrl`, `tunnel: "down"`).

The tunnel is its own detached process and outlives server restarts. The server checks it every
second: when cloudflared exits, the server starts a new one (backing off up to a minute while it
fails), allows the new host, and records the new link in `session.share` with `changedAt`, which
the owner's view shows as "New guest link, share again"; the next `ensure-running` says
`shareChanged: true`. `python tunnel.py adopt --dir D --pid N --url U --port P` records a
cloudflared that is already running, without starting anything; it is then watched and restarted
like one the server started.

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
| `add-asset` | `path`, `as?`, `scale?` | Copies a PNG, JPEG, WebP, SVG or HTML file (by its bytes, at most 10 MB) from the data folder or the system temp folder into `assets/<16 hex>.<ext>`, named by its content; returns `{id, kind, bytes, at, scale}`. Usable from the next apply |
| `make-question-from` | `proposal`, `question` | |
| `handle` | `seqs` | Marks events handled |

## Data contract

One folder per session: `<memory_dir>/<topic-slug>/shared/<session-slug>/`.

| Path | Writer | Mode | Holds |
|---|---|---|---|
| `state.json`, `state.v<N>.json` | server | 0600 | The session (`schema/state.schema.json`); the pre-migration copy |
| `defaults.json` | the skill | | Settings for a new session |
| `ops.json` | Claude | | One apply; deleted when it lands |
| `.shared-secrets.json` | server (made on first start) | 0600 | The control token and the owner token |
| `.owner-link` | server | 0600 | `http://127.0.0.1:<guest port>/#owner=<token>` |
| `.shared-session.json`, `.shared-session.env` | session-bridge `start` | 0600 | Control port, pid, control token, nonce |
| `.shared-ports.json` | server | 0600 | The guest and control ports, reused on every start |
| `.shared-tunnel.json` | `tunnel.py` | 0600 | `{pid, url, port, startedAt, marker, adopted}` |
| `cloudflared.log` | cloudflared | 0600 | Its output, where its address is read |
| `server.log` (+ `.1`..`.3`) | server | 0600 | One line per request (method, path, status, time); rotated at 1 MB, 3 kept |
| `.shared-server.err` | the server's stderr | 0600 | Why a start failed |
| `.shared-reported` | `share.py` | | The guest link the last `ensure-running` printed (for `shareChanged`) |
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
- **Requests.** JSON POSTs only (415), the 32 KB body cap checked before reading (413), a
  per-address limit (`CF-Connecting-IP` only, never `X-Forwarded-For`), and session.py's per-route
  write limit and join limit.
- **Headers.** Every answer: `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`,
  `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`. HTML adds the page policy
  (`default-src 'self'` ... `frame-ancestors 'none'; base-uri 'none'; form-action 'none'`).
  `/assets/*` adds `Content-Security-Policy: sandbox` (`allow-scripts` for HTML only, never
  `allow-same-origin`) and `Content-Disposition: inline`.
- **What a visitor reads.** Without identity, `/api/state` is `{title, ended, joinNeedsKey,
  schemaVersion}` only; a removed person and an owner link from before a rotation read nothing.
  Results stay hidden from guests until the owner publishes them.
- **Guest text is data.** Answers, chat, proposals and requests reach Claude in the digest,
  delivered with session-bridge's data note; an instruction in them is a finding, never a request.
- **Files.** `add-asset` reads only regular, non-hidden files under the data folder or the system
  temp folder, and only when the bytes are an allowed type.

Where each token can be seen:

| Token | Exposure paths |
|---|---|
| Owner token | `.shared-secrets.json` and `.owner-link` (0600); the owner's browser (the link's fragment, never sent to the server, and its history); the opener's command line for the moment `--open` hands the link to the browser; the transcript when the owner asks for `url --owner` |
| Guest secret | The guest's browser storage and personal link (`#me=` fragment); the `X-Session-Secret` header, which Cloudflare's edge sees because the tunnel terminates TLS there |
| Control token | `.shared-secrets.json`, `.shared-session.json`, `.shared-session.env` (0600); the `curl` command line `watch.sh` runs (the generated session-bridge watcher puts the header on argv), visible to the same user's process list |

Neither token is on the server's command line: the server reads both from the secrets file.
`stop` drops the control token, so the next start makes a new one; `restart` keeps it.

## Supported platforms

Windows, macOS and Linux. Process start, liveness and stop go through `detached.py`: POSIX gets
`start_new_session`, TERM and a zombie-aware pid check; Windows gets `DETACHED_PROCESS |
CREATE_NEW_PROCESS_GROUP` (breaking away from the caller's job when allowed), `OpenProcess` and
`GetExitCodeProcess`, and the guest port is bound with `SO_EXCLUSIVEADDRUSE`. A recorded pid
counts only while its command line (POSIX) or executable (Windows) names the expected program, so
a pid the OS reused is never stopped. File modes are 0600 where the OS has them; on Windows they
are advisory, so the data folder belongs under the user profile. `share.sh` runs under Git Bash;
`share.py` runs directly. cloudflared install hints are in `plugins/planning/prerequisites.json`.

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
