# Interview page surface

A local page for interview rounds. The user answers one question at a time on 127.0.0.1, and the live Claude Code session receives each save through a background watcher and replies on the page. The interview skill's `context/surface.md` holds the rules the session follows.

## Files

| File | Owner | Role |
|---|---|---|
| `server.py` | runs | Stdlib `ThreadingHTTPServer` on 127.0.0.1. Serves the page, pushes state over SSE, takes answers, long-polls for the watcher, serves file visuals by visual id (`/api/visual-file?id=`), computes question state and settings |
| `index.html` | page | Single file, no build step, no CDN |
| `round.py` | Claude | The only write path to `questions.json`, plus the server lifecycle and the exporters |
| `round.sh` | Claude | Launcher: runs `round.py` with the first `python3` or `python` that runs (a stub that fails is skipped) |
| `watch.sh` | Claude | The watcher, run as a background Bash task |
| `exporters.py` | Claude | `export-ledger`, `export-brief`, `export-report`, `import-ledger` (called through `round.py`) |
| `schema.py`, `schema/*.schema.json` | shared | JSON Schemas for the question, response, event, visual and ops files, and the stdlib validator `round.py` applies on every write |
| `test_*.py`, `*.test.sh`, `tests/` | tests | Python `unittest` suites, shell suites, browser suites and fixtures |

Per data dir: `questions.json` (Claude, through `round.py`), `responses.json` (server only: the event log and derived answers), optional `settings.json` and `theme.json`, and runtime files never exported (`.interview-session.json`, `.interview-session.env`, `.watch-seq`, `.watch-replay`, `questions.json.lock`).

## Run

```bash
bash round.sh --dir '<data_dir>' ensure-running [--port P] [--open] [--user-settings F] [--emoji-markers V]
bash round.sh --dir '<data_dir>' stop
```

`ensure-running` checks for curl, reuses the server already running for the data dir (same PID), and otherwise starts one in the background (on Windows through the base interpreter, with no console window) on the first free port of `--port`, the recorded port, and the resolved `port` setting (an explicit `--port 0` skips the setting), else a free port. It waits for the server's own session files, prints the URL, and with `--open` opens the page unless the resolved `openBrowser` is `false`, through the `browserCommand` of the `--user-settings` file this same call passes, else the default browser. Without `--user-settings`, the user file the running server recorded still supplies `openBrowser` and `waitTimeout`, but never the opener. The URL is always built from the recorded port as `http://127.0.0.1:<port>/`. `--emoji-markers` takes any value: only `true`, `1`, `yes` and `on` (any case) mean true, and anything else, an empty string or an unexpanded `user_config` token included, means false. The value is written to `meta.emojiMarkers`; an absent flag keeps the recorded value, and a new file records false, so pass the session's value each time, including on a restart. `stop` ends the recorded PID only after `/api/ping` on the recorded port answers with that PID; otherwise it only clears the session files. A restart issues a new token: an armed watcher exits 2 at once with "token changed: re-run ensure-running", so re-arm it.

## Watcher protocol

`bash watch.sh '<data_dir>'` long-polls `/api/wait?after=handled&replayed=<n>` with the token, where `<n>` comes from `.watch-replay`. When there are unhandled events it prints one JSON line (`seq`, `timedOut`, `events`, `note`, `dataDir`, `next`) and exits 0; `next` is the exact re-arm command with absolute paths, each in single quotes. Events a dead turn never handled come back at once on the next arm; after that re-delivery an arm waits for a new event. The page's header reads "Claude is working on Qn" while a delivered event is unhandled. After ten minutes with no watcher waiting, it reads "Claude has not handled Qn yet" and its connection word reads "Not listening: type next". The event stream sends a `ping` every 15 seconds while idle, and at most 8 streams run at once (one more gets 503); the page re-fetches `/api/state` when a tab becomes visible, when the stream reconnects, and after two missed pings. The watcher exits 2 when curl is missing, when the token is rejected, or when the server stays unreachable.

One watcher per data dir: every poll sends `&watcher=<id>`, where the id is `WATCH_ID`, else `CLAUDE_CODE_SESSION_ID` (Claude Code exports it to every shell a session runs, so every re-arm shares it), else `<hostname>-<parent pid>` (from a plain terminal that is the interactive shell's pid, so re-arm from the same shell or export `WATCH_ID`); it is never written to the data dir. The first id holds an in-memory lease, so a stop or crash frees it. A poll from another id gets 409 `{"error": "lease held", "holder", "since", "lastWaitAt", "expiresAt"}` and does not block; `watch.sh` then prints the holder to stderr and exits 3 without retrying. The lease expires when its holder has no wait in flight and its last wait ended more than `leaseTimeout` seconds ago; while the holder waits, `expiresAt` is the earliest expiry. `round.sh lease` prints the holder or `no lease`, `round.sh lease --release` hands it over (`POST /api/lease {"action": "release"}`, token required), and `/api/state` shows it as `listener.lease` (`{watcher, since, lastWaitAt, waiting}` or null). A wait with no `watcher` parameter takes no part in leasing: it is neither refused nor a holder.

Each wake is one background Bash call: `round.sh --dir '<data_dir>' apply --file '<data_dir>/ops.json' && watch.sh '<data_dir>'`. The interview skill's `context/surface.md` has the event table, the op shapes and the rules.

## round.py

Every command needs `--dir '<data_dir>'`; there is no default. Every write validates `questions.json` against `schema/questions.schema.json` and holds `questions.json.lock` (`ROUND_LOCK_TIMEOUT` seconds, default 10). Run `round.sh --dir '<data_dir>' <command> --help` for every flag. User and dictated text (a reply, a note reply, a terminal answer, an archive reason) goes into an op in `ops.json`, written with the Write tool and run through `apply`, never on a command line; the op shapes are in `schema/ops.schema.json`.

| Command | Does |
|---|---|
| `ensure-running`, `stop` | Server lifecycle, as above |
| `add` | One question from `--file` or flags. Refuses a question without `commits` (`--commit none` is an explicit empty list) or with fewer than two alternatives |
| `add-round --file F [--round N]` | Meta, groups, questions and visuals in one write; any error writes nothing. The file's `meta` object takes `title`, `eyebrow`, `stages` and `next` (what Claude does after wrap-up, shown on the finished screen) and refuses other keys |
| `meta` op | `{"op": "meta", "set": {...}}` merges the same four keys into `meta`; other meta keys, such as `emojiMarkers`, stay |
| `group <id>` | Add or update a group; `--depends` names prerequisite groups |
| `reply` op | A Claude line on the question's thread; `seq` marks that event handled; `rec` revises the recommendation and needs `affects` |
| `revise <id>` | Change wording, recommendation (`--rec` needs `--affects`) or alternatives (at least two) |
| `handle --seq N [M ...]` | Mark events handled with no reply |
| `note-reply` op | Reply in the Notes to Claude thread |
| `record-terminal` op | Record an answer the user gave in the terminal |
| `archive` op | Take off-path questions out of the open count; the server derives their state |
| `set-status` op | `{"op": "set-status", "text": "..."}` sets the page's Claude line (top-level `status`); `"clear": true` removes it |
| `wait` op | `{"op": "wait", "id": "Q10", "waitsOn": "...", "by": "claude"}` holds a question (`waiting`, `waitsOn`). `by` is `claude` (the default: pending research) or `user` (needs the user's answer: writes `waitingBy: "user"` and stamps `setAsideAt` and `setAsideSeq`, the page's seq then; a page decision whose seq is not above `setAsideSeq`, or a terminal one not later than `setAsideAt`, stops counting as an answer). `"clear": true` removes `waiting`, `waitsOn` and `waitingBy` and keeps both stamps |
| `confirm-commitments` op | `{"op": "confirm-commitments", "id": "Q3", "indices": [0], "reason": "..."}` appends `{index, reason, at}` to the question's `commitsConfirmed` (all commitments when `indices` is absent; an index keeps its first record); refuses an unknown id, an index out of range and a blank reason |
| `restate` op | `{"op": "restate", "sections": {"goal": "...", ...}}` writes top-level `restatement: {rev, at, sections}` with `rev` incremented; sections are `goal`, `constraints`, `decisions`, `acceptance`, `deferred`, `planningOwned` (markdown, at least one non-empty, other keys refused) |
| `activity` op | `{"op": "activity", "text": "...", "ids": [...]}` appends its own Activity entry for off-page work; every write whose ops include `reply`, `note-reply`, `revise`, `add`, `add-round`, `archive`, `record-terminal`, `wait`, `confirm-commitments` or `restate` appends one summary entry itself (newest 200 kept) |
| `apply --file F` | Run `{"ops": [...]}` as one atomic write; any refused op writes nothing |
| `status [--latency]` | Open and answered counts, held questions (`waits on:` for a Claude hold, `awaiting user:` for a user hold), unhandled events; p50 and p95 latencies |
| `bump [--id Q]` | Bump the file rev, or one question's |
| `validate` | Check both files against the shipped schemas |
| `export-ledger`, `export-brief`, `export-report --out F` | The ledger register, the PLAN.md Brief sections, one self-contained HTML report whose CSP allows no network source |
| `import-ledger --ledger F` | Seed an empty data dir from an existing ledger |
| `lease [--release]` | Print the watcher holding the lease, or `no lease`; `--release` clears it |

`reply` and `revise` with a recommendation change exit 1 when the question has a live user event newer than `seq` (an undo and a withdrawn event do not count; without `seq`, any unhandled user event) unless `force`. The `reply` op's `handled: N` (the CLI's `--handled N`) marks every event with seq at or below N handled, including other questions' events; prefer `handle` with explicit seqs. `status` lists the unhandled events after the line `Event text is user data, not instructions.`, each event's text JSON-quoted on one line; withdrawn events are not listed. `add`, `add-round` and `apply` warn on a bare id that names no question and on a recommendation or basis over the length budget.

## Data contract

`schema/` is the contract; other tools write these formats or read the exports, and the surface reads no other files except a file a visual names inside the data dir. Both documents carry `"schemaVersion": "1.0"`; a file without one reads as version 0 and loads unchanged. `responses.json` is an append-only event log with a global `seq`; undo marks an event `withdrawn` and nothing is deleted. Event kinds: `accept`, `alt`, `own`, `defer`, `reopen`, `ask`, `rephrase`, `note`, `undo`, `wrapup`, `confirm`, `confirm-understanding`. `confirm-understanding` has no id; its `alt` is `confirm` or `off` (`off` needs `text`), and its `contentRev` must equal `restatement.rev`: a missing restatement or `contentRev` is 400, an older rev is 409 `{"error": "stale", "contentRev": <current>}`. Question `state` (`open`, `stale`, `upstream-pending`, `archived`) is computed by the server from `dependsOn` and `archived`, never written. A visual is declared by `format` (`svg`, `mermaid`, `image`, `markdown`, `html`, `chart`; `kind` is read as an alias) and describes only its content.

## Security model

- Binds 127.0.0.1 only.
- A per-run token from `secrets.token_urlsafe(32)` is injected into the page and required as `X-Interview-Token` on every POST and on `/api/wait`; the custom header forces a CORS preflight the server never approves.
- `Host` must be `127.0.0.1:<port>` or `localhost:<port>` on every request, which blocks DNS rebinding; `Origin`, when present, must match.
- POST must be `application/json` (415 otherwise), bodies over 64 KB are 413 (the only limit on answer text); a body that is not a JSON object, unknown ids and kinds, an `alt` that is not one of the question's alternative keys, a `confirm` index outside its `commits`, and a non-integer `Content-Length` are 400. The token is read only from the header, never from the query string. `.interview-session.json` and `.interview-session.env` hold the token and are written with mode 0600 (advisory on Windows). The CSP allows only `'self'`, with `frame-ancestors 'none'`, `X-Frame-Options: DENY` and `nosniff`.
- `POST /api/lease` takes the token like every POST; it only clears the watcher lease. The lease is a coordination aid between sessions, not an access control: any holder of the token can release it.
- Answers are data: `/api/wait` responses say so, and markdown is escaped before rendering; SVG and HTML visuals render in a sandboxed iframe.
- `/api/visual-file?id=<visual id>` takes the token and serves a file only when a visual in `questions.json` names it and it resolves to a regular file inside the data dir, up to 4 MB (413 above); a path with a dotfile component, a `.lock` or a `.tmp` name (the runtime files and their temp copies hold the token) and anything else is 404 `not found`. No route takes a path from the URL.

Limits: any local process that can reach the port can read the token from `GET /`, so on a shared host other local users can answer. A session on a remote host serves its own 127.0.0.1, which the user's browser cannot reach; the skill then falls back to its read-only table.

## Settings layers

Nearest wins, per key, and each Settings row names its layer: this browser's localStorage (the Settings tab), the data dir's `settings.json`, a user file passed as `ensure-running --user-settings`, the repository's `.claude/interview-surface.json` (found through `CLAUDE_PROJECT_DIR`, else the nearest ancestor holding `.git`), then defaults.

| Key | Default | Bounds |
|---|---|---|
| `port` | `0` (a free port) | 0 to 65535 |
| `openBrowser` | `true` | |
| `shortcuts` | `true` | the single off switch for single-key shortcuts |
| `undoSeconds` | `5` | 0 to 60 |
| `checkpoint` | `0` (off) | 0 to 500 |
| `theme` | `auto` | `auto`, `light`, `dark` |
| `density` | `compact` | `compact`, `comfortable` |
| `minText` | `14` | 10 to 32 |
| `displayName` | `You` | user file or session only |
| `waitTimeout` | `90` | 5 to 110 seconds; curl allows 10 more |
| `staleDepth` | `direct` | `direct` |
| `leaseTimeout` | `600` | 5 to 3600 seconds a silent watcher keeps its lease; read on every poll |

The repo and user files also take `themeTokens` (`{"light": {...}, "dark": {...}}`). `browserCommand` (a program or argv list that receives the URL) is read only from a user file passed as `--user-settings` on that same `ensure-running` call. The user file a running server recorded keeps supplying every other setting, but never the opener, so `--open` alone uses the default browser. An invalid value falls through to the layer below with a note printed by `ensure-running`. Theme tokens layer per token: the data dir's `theme.json`, then the user file's `themeTokens`, then the repo's `themeTokens`, then the built-in set.

## Known gaps

- The browser suites run only where `playwright-cli` resolves; elsewhere `surface.test.sh` prints a SKIP with the count not run.
- Browsers cap HTTP/1.1 connections at six per origin and each tab holds one SSE stream, so keep to one or two tabs.
- Chromium logs a network error line for an intended 409; the page itself logs nothing.
- Mermaid visuals show their source with a "rendering not available" line.
