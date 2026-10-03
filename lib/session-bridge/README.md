# session-bridge

Carries a local page's events to a live Claude Code session. Two apps run on it: the planning
interview page, and the view app behind Claude-interactive views (the work-items triage board and
the planning plan view).

## Files

| File | Role |
|---|---|
| `session_bridge.py` | The `Transport` port, the loopback adapter (`LoopbackWatcher`, `LoopbackHandler`, `start`, `serve`), the client half the app's control script runs, the channels adapter (`ChannelRelay`, `ChannelServer`) and `select_transport` |
| `watch.sh` | The watcher: long-polls `/api/wait` from a background Bash task and prints one JSON line when there are events |
| `wake.sh` | One wake: the app's `apply` on `<data_dir>/ops.json`, then `watch.sh` |
| `test_session_bridge.py` | Tests against a toy app: port, guards, long-poll, lease, event stream, client, `watch.sh` and `wake.sh`, adapter selection, and the channel server over stdio |
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

The server also ends on its own once no watcher wait has been in flight for `IDLE_SECONDS` (600, the
lease timeout; `--idle-seconds` overrides it), and clears its session files. The watcher is a
background task of the session that armed it, so a session that ends stops polling and its token
stops working about 600 seconds after its last wait. A session that leaves the watcher down that long
loses the server too: `watch` then exits 2 asking for `ensure-running`, which starts a server with a
new token on the same port, and the reader reloads the page.

## Rendered-views rule 9

| Rule 9 bullet | How it holds |
|---|---|
| The page sends only reader input and builder ids | `view-runtime.js` sends picked row ids, option keys and textarea text; `view_bridge.py` refuses anything else |
| Page fields reach the session as data, never as the user's message | `DATA_NOTE` on every wait answer, delivered as background-task output (Delivery as data) |
| An unguessable per-session token authenticates every message | `secrets.token_urlsafe(32)` per server run, required on every POST and wait, handed only to same-origin page script, gone when the server stops; the server stops by itself about 600 s after the session's watcher last waited, so the token expires with the session |
| No message triggers a gated action without its gate | The bridge and the view app store and deliver; nothing in either acts on an event |

## The channels adapter

Claude Code's native [channels](https://code.claude.com/docs/en/channels) are a research preview:
an MCP server the session spawns pushes `notifications/claude/channel` events into it
([channels reference](https://code.claude.com/docs/en/channels-reference)). Verified 2026-10-03;
recheck when either page changes the flags, the `claude/channel` capability or the policy keys.

- `session_bridge.py relay` runs `ChannelServer`, a stdio MCP server that declares the
  `claude/channel` capability and three tools taking `data_dir`: `watch`, `events` and `unwatch`.
  It reads `NAME` and `CONTROL` from `session-bridge.conf` beside it, as `watch.sh` does.
- `watch` starts a `ChannelRelay` for the data dir. The relay implements the port against the page
  server: it long-polls `/api/wait` with the token from the 0600 env file and holds the lease in
  place of `watch.sh`, so the page shows the session as listening. Its log is the batch the page
  server delivered that the session has not read yet.
- On new events the relay rings the session with one channel event. The event names only the data
  dir, `seq` and `count`; it never carries page text, so nothing from the page reaches the session
  as a channel message. `events` returns the batch in `watch.sh`'s line shape, with the data note,
  and `next` is the app's apply command (`CONTROL --dir <data_dir> apply --file <data_dir>/ops.json`).
  No re-arm is needed: the relay keeps polling and does not ring again for events it already rang.
- A 409 (lease held or released), a changed token, the page server stopping, or 12 unreachable
  polls end the relay; it rings once more with `stopped="1"` and the reason. `unwatch` releases the
  lease and rings nothing.
- The relay's poll records its own pid, and `end_watcher` signals only a `watch.sh`, so the app's
  `stop` never signals the channel server.

An app ships the relay by registering `session_bridge.py relay` in its plugin's `.mcp.json`; the
person then starts the session with `--channels plugin:<plugin>@<marketplace>` (only when the
organization's `allowedChannelPlugins` lists it) or
`--dangerously-load-development-channels plugin:<plugin>@<marketplace>`. No app ships it yet: the
planning interview stays on the loopback watcher.

## Choosing the adapter

`select_transport(entries)` (or `session_bridge.py select <entry>...`) returns
`{"transport": "channels" | "loopback", "reason": ...}`, where `entries` are the relay's flag forms
(`plugin:<plugin>@<marketplace>`, `server:<name>`). It picks channels only when every check below
passes, in this order, and otherwise keeps the loopback watcher and names the first failed check.
An input it cannot read counts as failed, so an unknown never selects channels.

| Check | Reads | Keeps loopback when |
|---|---|---|
| Provider | `CLAUDE_CODE_USE_BEDROCK`, `_VERTEX`, `_FOUNDRY`, `_MANTLE`, `_ANTHROPIC_AWS` | Any is set: channels need claude.ai or Console auth |
| Session opt-in | The argv of the nearest ancestor naming `--channels` or `--dangerously-load-development-channels` (`/proc`, else `ps`) | No entry is named, or the ancestors cannot be read (Windows) |
| Auth | `claude auth status --json` | It cannot be read, `loggedIn` is not true, or `apiProvider` is not `firstParty` |
| Organization | The first managed source with a policy key: the server-managed cache (`~/.claude/remote-settings.json`), then `managed-settings.json` with `managed-settings.d/*.json` | A source exists without `channelsEnabled: true`, or none exists and `subscriptionType` is `team` or `enterprise` |
| Allowlist | `allowedChannelPlugins` in that source | The entry came by `--channels` and the list does not name its plugin and marketplace |

MDM policies (a macOS plist, the Windows registry) are not read, so a policy delivered only by
MDM reads as none. Claude Code drops channel events silently when a policy blocks them; its
startup notice says so.

## Prerequisites

The channels adapter's prerequisites. Each one's absence keeps the loopback watcher, which needs
none of them. A plugin that registers the relay adds the `claude` row to its `prerequisites.json`;
the others are not checker kinds, and `select_transport` reports them.

| id | need | detect | degrade |
|---|---|---|---|
| `claude` | optional | `claude auth status --json` | Without it the session's auth cannot be read, so the session keeps the loopback watcher. |
| `anthropic-auth` | optional | `loggedIn` and `apiProvider: firstParty`, no third-party provider variable | On Bedrock, Agent Platform, Foundry or another provider, channels are unavailable; the loopback watcher carries events as before. |
| `channels-opt-in` | optional | The session's launch flags name the relay | A session started without the flag keeps the loopback watcher. |
| `org-channels-enabled` | optional | `channelsEnabled: true` in a readable managed source, or a plan with no organization checks | A Team or Enterprise organization that has not enabled channels, or a managed policy without `channelsEnabled: true`, keeps the loopback watcher. |

## Tests

```bash
cd lib/session-bridge && python3 -m unittest test_session_bridge test_view_bridge
```
