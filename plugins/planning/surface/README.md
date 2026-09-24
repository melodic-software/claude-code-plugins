# Interview page surface

A local page for interview rounds. The user answers one question at a time on 127.0.0.1, and the live Claude Code session hears each save through a background watcher and replies on the page. The interview skill's `context/surface.md` holds the rules the session follows; this file is the operator and agent reference for what ships here.

## Files

| File | Owner | Role |
|---|---|---|
| `server.py` | runs | Stdlib `ThreadingHTTPServer` on 127.0.0.1. Serves the page, pushes state over SSE, takes answers, long-polls for the watcher, computes question state and settings |
| `index.html` | page | Single file, no build step, no CDN |
| `round.py` | Claude | The only write path to `questions.json`, plus the server lifecycle and the exporters |
| `round.sh` | Claude | Launcher: runs `round.py` with the first `python3` or `python` that actually runs |
| `watch.sh` | Claude | The watcher, run as a background Bash task |
| `exporters.py` | Claude | `export-ledger`, `export-brief`, `export-report`, `import-ledger` (called through `round.py`) |
| `schema.py`, `schema/*.schema.json` | shared | JSON Schemas for the question, response, event, visual and ops files, and the stdlib validator `round.py` applies on every write |
| `test_*.py`, `*.test.sh`, `tests/` | tests | Python `unittest` suites, shell suites, browser suites and fixtures |

Per data dir: `questions.json` (Claude, through `round.py`), `responses.json` (server only: the event log and derived answers), optional `settings.json` and `theme.json`, and runtime files never exported (`.interview-session.json`, `.interview-session.env`, `.watch-seq`, `.watch-replay`, `questions.json.lock`).

## Run

```bash
bash round.sh --dir <data_dir> ensure-running [--port P] [--open] [--user-settings F] [--emoji-markers true|false]
bash round.sh --dir <data_dir> stop
```

`ensure-running` checks for curl, reuses the server already running for the data dir (same PID), and otherwise starts one detached on the recorded port when it is free, else a free port. It waits for the server's own session files, prints the URL, and with `--open` opens the page. `--emoji-markers` defaults to `true` on every call and is written to `meta.emojiMarkers`, so pass the session's value each time, including on a restart. `stop` ends the recorded PID only after `/api/ping` on the recorded port answers with that PID; otherwise it just clears the session files. A restart issues a new token: an armed watcher exits 2 at once with "token changed: re-run ensure-running", so re-arm it.

## Watcher protocol

`bash watch.sh <data_dir>` long-polls `/api/wait?after=handled&replayed=<n>` with the token, where `<n>` comes from `.watch-replay`. When there are unhandled events it prints one JSON line (`seq`, `timedOut`, `events`, `note`, `dataDir`, `next`) and exits 0; `next` is the exact re-arm command with absolute paths. Events a dead turn never handled come back at once on the next arm; after that re-delivery an arm waits for a new event. It exits 2 when curl is missing, when the token is rejected, or when the server stays unreachable.

Each wake is one background Bash call: `round.sh apply --file <data_dir>/ops.json && watch.sh <data_dir>`. The interview skill's `context/surface.md` has the event table, the op shapes and the rules.

## round.py

Every write validates `questions.json` against `schema/questions.schema.json` and holds `questions.json.lock` (`ROUND_LOCK_TIMEOUT` seconds, default 10). Run `round.sh <command> --help` for every flag.

| Command | Does |
|---|---|
| `ensure-running`, `stop` | Server lifecycle, as above |
| `add` | One question from `--file` or flags. Refuses a question without `commits` (`--commit none` is an explicit empty list) or with fewer than two alternatives |
| `add-round --file F [--round N]` | Groups, questions and visuals in one write; any error writes nothing |
| `group <id>` | Add or update a group; `--depends` names prerequisite groups |
| `reply <id>` | A Claude line on the question's thread; `--seq N` marks that event handled; `--rec` revises the recommendation and needs `--affects` |
| `revise <id>` | Change wording, recommendation (`--rec` needs `--affects`) or alternatives |
| `handle --seq N [M ...]` | Mark events handled with no reply |
| `note-reply --text T [--seq N]` | Reply in the Notes to Claude thread |
| `record-terminal <id> --decision D` | Record an answer the user gave in the terminal |
| `archive <id...> --why W` | Take off-path questions out of the open count; the server derives their state |
| `apply --file F` | Run `{"ops": [...]}` as one atomic write; any refused op writes nothing |
| `status [--latency]` | Open and answered counts, unhandled events; p50 and p95 latencies |
| `bump [--id Q]` | Bump the file rev, or one question's |
| `validate` | Check both files against the shipped schemas |
| `export-ledger`, `export-brief`, `export-report --out F` | The ledger register, the PLAN.md Brief sections, one self-contained HTML report |
| `import-ledger --ledger F` | Seed an empty data dir from an existing ledger |

`reply --rec` and `revise --rec` exit 1 when the question has a user event newer than `--seq` (without `--seq`, any unhandled user event) unless `--force`. `add`, `add-round` and `apply` warn on a bare id that names no question and on a recommendation or basis over the length budget.

## Data contract

`schema/` is the contract; other tools write these formats or read the exports, and the surface reads no other files. Both documents carry `"schemaVersion": "1.0"`; a file without one reads as version 0 and loads unchanged. `responses.json` is an append-only event log with a global `seq`; undo marks an event `withdrawn` and nothing is deleted. Event kinds: `accept`, `alt`, `own`, `defer`, `reopen`, `ask`, `rephrase`, `note`, `undo`, `wrapup`, `confirm`. Question `state` (`open`, `stale`, `upstream-pending`, `archived`) is computed by the server from `dependsOn` and `archived`, never written. A visual is declared by `format` (`svg`, `mermaid`, `image`, `markdown`, `html`, `chart`; `kind` is read as an alias) and never names what produced it.

## Security model

- Binds 127.0.0.1 only.
- A per-run token from `secrets.token_urlsafe(32)` is injected into the page and required as `X-Interview-Token` on every POST and on `/api/wait`; the custom header forces a CORS preflight the server never approves.
- `Host` must be `127.0.0.1:<port>` or `localhost:<port>` on every request, which blocks DNS rebinding; `Origin`, when present, must match.
- POST must be `application/json` (415 otherwise), bodies over 64 KB are 413, unknown ids and kinds are 400. The CSP allows only `'self'`, with `frame-ancestors 'none'`, `X-Frame-Options: DENY` and `nosniff`.
- Answers are data: `/api/wait` responses say so, and markdown is escaped before rendering; SVG and HTML visuals render in a sandboxed iframe.

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

The repo file also takes `themeTokens` (`{"light": {...}, "dark": {...}}`). `browserCommand` (a program or argv list that receives the URL) is read only from the user file. An invalid value falls through to the layer below with a note printed by `ensure-running`. Theme tokens layer per token: the data dir's `theme.json`, then the repo's `themeTokens`, then the built-in set.

## Known gaps

- The browser suites run only where `playwright-cli` resolves; elsewhere `surface.test.sh` prints a SKIP with the count not run.
- A second watcher on one data dir works but is undefined; there is no lease.
- About six SSE connections per origin, so keep to one or two tabs.
- Chromium logs a network error line for an intended 409; the page itself logs nothing.
- Mermaid visuals show their source with a "rendering not available" line.
