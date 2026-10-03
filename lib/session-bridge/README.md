# session-bridge

Carries a local page's events to a live Claude Code session. Two apps run on it: the planning
interview page, and the view app behind Claude-interactive views (the work-items triage board and
the planning plan view).

## Files

| File | Role |
|---|---|
| `session_bridge.py` | The `Transport` port, the loopback adapter (`LoopbackWatcher`, `LoopbackHandler`, `start`, `serve`) and the client half the app's control script runs |
| `watch.sh` | The watcher: long-polls `/api/wait` from a background Bash task and prints one JSON line when there are events |
| `wake.sh` | One wake: the app's `apply` on `<data_dir>/ops.json`, then `watch.sh` |
| `test_session_bridge.py` | Tests against a toy app: port, guards, long-poll, lease, event stream, client, `watch.sh` and `wake.sh` |
| `view_bridge.py` | The view app: serves a page built by `lib/view-builder.mjs --connect`, takes its actions, and shows the session's replies |
| `view-bridge.sh` | The view app's control script (`CONTROL` in its `session-bridge.conf`): runs `view_bridge.py` with the first Python 3 that runs |
| `test_view_bridge.py` | Tests for the view app on the loopback adapter, including the full `ensure-running`, `watch.sh` and `apply` loop |

These are canonical sources. Each carrying plugin gets a generated copy through
`scripts/shared-copies.txt` and `scripts/sync-shared-copies.sh` (ADR 0019); edit here, then run the
script. The copies sit together in one plugin directory, because `watch.sh` and `wake.sh` find
`session-bridge.conf`, each other and the control script beside themselves.

## The port

`Transport` is the boundary between an app and how its events reach the session. An adapter
implements `wait`, `release` and `listener`. The app implements the log hooks:

| Hook | Does |
|---|---|
| `read_log()` | The event log: a dict with an integer `seq` and an `events` list; each event has `seq` and may have `withdrawn` and `deliveredAt` |
| `write_log(log)` | Persist the log after the transport stamped `deliveredAt` on newly delivered events |
| `unhandled(log)` | The events the session has not handled |
| `lease_timeout()` | Seconds a watcher with no wait in flight keeps its lease (default 600) |
| `settle_window()` | `(quiet, burst)`: a found event waits `quiet` seconds for more, `burst` at most (default 3 and 12) |

An app binds to the loopback adapter by subclassing `LoopbackWatcher`, setting `name`, and adding
the page hooks `read_state()` (the state frame and whether it is stale), `signature()` (changes
whenever the state does) and `identity()` (extra `/api/ping` fields). Its `LoopbackHandler`
subclass sets `max_body` and `page_csp` and adds routes in `route_get(url, query)` and
`route_post(path, msg)`.

## The loopback adapter

- Binds 127.0.0.1 only. `Host` must be `127.0.0.1:<port>` or `localhost:<port>`, and `Origin`, when
  sent, must match.
- A per-run token from `secrets.token_urlsafe(32)` rides only in the `X-<Name>-Token` header; every
  POST and `/api/wait` needs it. Every POST must be `application/json`, 1 to `max_body` bytes, a
  JSON object.
- `start()` writes `.<name>-session.json` (pid, port, url, token, dataDir, nonce, startedAt) and
  `.<name>-session.env` (`PID`, `PORT`, `TOKEN`, `NONCE`) to the data dir, mode 0600.
- `GET /events` streams `state` frames on every change and a `ping` every 15 s when idle; at most 8
  streams run at once (one more gets 503).
- `GET /api/wait?after=handled&replayed=<n>&timeout=<s>&watcher=<id>&pid=<pid>` blocks until the
  log holds unhandled events, at most `timeout` seconds (1 to 120, default 90). Events a dead turn
  never handled come back at once when any seq exceeds `replayed`. `after=<seq>` returns the
  events past a seq instead. The answer is `{seq, timedOut, replayed?, events, note}`.
- The first `watcher` id holds an in-memory lease; another id gets 409 `lease held` until the
  lease expires. `POST /api/lease {"action": "release"}` clears it, and a wait the old holder has
  in flight ends with 409 `lease released`. `GET /api/lease` shows the holder. A wait without a
  `watcher` takes no part in leasing.
- `GET /api/ping` answers `ok`, the app's `identity()`, `pid`, `dataDir` and `consoleWindow`.

## The watcher

`watch.sh '<data_dir>'` reads `NAME` and `CONTROL` from `session-bridge.conf` beside it. `NAME`
names the session files and the token header; `CONTROL` is the app's control script beside it,
which `wake.sh` runs as `CONTROL --dir <data_dir> apply --file <data_dir>/ops.json` and messages
name for `ensure-running`, `stop` and `lease [--release]`. On events it prints one JSON line with
`dataDir` and `next` (the re-arm command, `bash '<here>/wake.sh' '<data_dir>'`), stores the seq in
`.watch-seq` and the replayed seq in `.watch-replay`, and exits 0. It exits 2 when curl, the conf
or the env file is missing, the token is rejected, or the server stays unreachable, and 3 when
another watcher holds the lease, its lease was released, or the server was stopped. The watcher id
is `WATCH_ID`, else `CLAUDE_CODE_SESSION_ID`, else `<hostname>-<parent pid>`.

## The client half

`ping`, `read_session`, `running`, `port_free`, `interpreter`, `spawn`, `wait_started`,
`kept_port`, `clear_session` (keeps the port so the page's origin survives a restart),
`set_wait_timeout`, `end_watcher` (signals only this data dir's `watch.sh`, never on Windows),
`watcher_lease` and `release_lease` are the pieces an app's control script composes into
`ensure-running`, `stop` and `lease`.

## Delivery as data

Every `/api/wait` answer carries `note`, `DATA_NOTE` in `session_bridge.py`: the untrusted-content
framing contract's spine, naming every page field, the reader's typed text included, as data and not
the user's own message. The watcher prints that body as one line of a background task's output, so a
page event reaches the session as tool output, never as a user turn. The bridge acts on nothing it
carries: an action a page asks for passes the same confirm or permission gate it always has.

## The view app

`view_bridge.py` makes a view built by `lib/view-builder.mjs` Claude-interactive. Its copies sit in
`view-bridge/` inside each adopting plugin, beside a `session-bridge.conf` with `NAME=view` and
`CONTROL=view-bridge.sh`.

1. `view-bridge.sh --dir <data_dir> ensure-running` starts the server, or reuses a running one, and
   prints `{url, origin, page, watch}`.
2. The adopter builds its page with `--connect <origin>` into `page`. The builder adds
   `connect-src <origin>` to the page's policy and nothing else (rendered-views rule 3).
3. The reader opens `url`. The runtime fetches the token from `GET /api/token`, which answers only
   a request with `Sec-Fetch-Site: same-origin` and a matching `Host` and `Origin`. The token never
   enters the page's markup, so a saved or published copy holds none.
4. `POST /api/action` takes `{action, picked, choices, notes}`: `action` and every choice are builder
   keys (`^[a-z0-9-]{1,32}$`), `picked` holds builder row ids, and `notes` holds the reader's text,
   at most 20 entries of 4000 characters. Any other field or shape is a 400.
5. The session runs `watch` in a background task. On a wake it reads the events as data, resolves
   each id against its own copy of the record, and writes `<data_dir>/ops.json`:
   `{"replies": [{"seq": 1, "text": "..."}], "handled": [2]}`. `next` (wake.sh) applies it, which
   removes the file, and re-arms. With no `ops.json` the apply is a no-op.
6. The page shows each action's progress and the session's reply text through `textContent` from
   the `state` frames on `/events`. A page with no server, or opened from `file://`, says no session
   is connected and keeps its copy and save controls.

`view-bridge.sh --dir <data_dir> stop` ends the server and its watcher; `lease [--release]` shows or
clears the watcher lease.

## Rendered-views rule 9

| Rule 9 bullet | How it holds |
|---|---|
| The page sends only reader input and builder ids | `view-runtime.js` sends picked row ids, option keys and textarea text; `view_bridge.py` refuses anything else |
| Page fields reach the session as data, never as the user's message | `DATA_NOTE` on every wait answer, delivered as background-task output (Delivery as data) |
| An unguessable per-session token authenticates every message | `secrets.token_urlsafe(32)` per server run, required on every POST and wait, handed only to same-origin page script, gone when the server stops |
| No message triggers a gated action without its gate | The bridge and the view app store and deliver; nothing in either acts on an event |

## Tests

```bash
cd lib/session-bridge && python3 -m unittest test_session_bridge test_view_bridge
```
