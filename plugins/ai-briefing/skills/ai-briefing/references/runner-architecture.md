# Per-Profile Runner — Stage CLI Architecture (Option A)

The runner is an **invocable stage library**, not an autonomous orchestrator. The main interactive Claude Code session drives the per-profile loop: it calls each subcommand between chrome MCP captures and `claude -p` subagent invocations.

## Why Option A

Two architectural facts force this design:

1. **Plugin-defined MCP servers do not load in `claude -p` subprocesses.** Per [code.claude.com/docs/en/mcp-servers#plugin-provided-mcp-servers](https://code.claude.com/docs/en/mcp-servers#plugin-provided-mcp-servers): *"When a plugin is enabled, its MCP servers start automatically"* — that auto-start happens for the **interactive** session that activated the plugin, not for headless `-p` subprocesses. The `claude -p` flag does NOT inherit plugin context; an `--mcp-config <path>` would be required for any subprocess to see MCP servers, and the chrome-in-chrome plugin does not ship a standalone server JSON that could be passed that way. Reference: [code.claude.com/docs/en/cli-reference](https://code.claude.com/docs/en/cli-reference) `--mcp-config` / `--strict-mcp-config` flags.
2. **The chrome-in-chrome extension supports exactly one CC↔Chrome WebSocket connection.** Even if `claude -p` could load the plugin, parallel subprocesses would compete for the same socket and fail.

**Conclusion.** S1 (chrome capture) MUST execute in the main interactive CC session. S3 + S4 are pure text in/out (no MCP) — `claude -p` works fine and stays the canonical path for those.

The earlier "Option B" (autonomous claude-p driver inside the runner) was empirically broken: `claude -p` subprocesses do not inherit the interactive session's plugin MCP connection, so chrome-in-chrome capture cannot run there. Option A (main-session-orchestrated Wave 1) is the canonical path.

## Module map

```text
scripts/
├── per-profile-runner.js              # entry — subcommand dispatcher
├── package.json                       # { "type": "module", "dependencies": { "zod": "^4.0.0" } }
├── anti-bot-pause.test.js             # anti-bot cap pause + resume-paused cycle
├── chrome-extraction.test.js          # extractor schema + parseAbbreviated + slimForPrompt
├── chunked-retrieval.test.js          # assembleChunks across chunk boundaries
├── mid-run-resume.test.js             # auto-resume after interrupted run
├── retry-failed-audit.test.js         # retry-failed list + stage subcommand reprocess
├── stage-cli-orchestration.test.js    # full subcommand sequence (mocked captures, dry-run)
└── lib/
    ├── async-seq.js                   # sequential async map/forEach/find
    ├── anti-bot.js                    # navs counter, pause logic, random delays
    ├── chrome-extract.js              # posts/replies/probe templates + URL/JS builders + zod validator
    ├── state.js                       # RunState + master.json + per-profile JSON + atomic writes
    ├── synthesize-agent.js            # S3 — claude -p Sonnet, zod CandidatesArraySchema
    ├── categorize-agent.js            # S4 — claude -p Sonnet, zod ItemsArraySchema
    └── terminal.js                    # Biome-safe stdout/stderr + createTestReporter
```

## CLI surface

```text
node per-profile-runner.js <subcommand> [flags]
```

stdout = single-line JSON. Logs/progress to stderr. Errors → JSON `{error: msg}` stdout + non-zero exit.

| Exit | Meaning |
|---|---|
| 0 | Success |
| 1 | Paused (anti-bot cap reached) |
| 2 | Hard fatal (filesystem error, master corrupt, no following-list, missing flag) |
| 3 | Completed with `failed` profiles present |

### Subcommands

#### `init [--scope=<>] [--cutoff=<ISO>] [--anti-bot-cap=N] [--with-replies-medium] [--no-replies] [--dry-run] [--force] [--grok-preload] [--grok-model=<slug>] [--require-grok]`

Mints fresh `run_id`, builds `ordered_handles` from `following-list.json`, writes `master.json`. Refuses to start if a run is already `in_progress`/`paused` (use `--force` to override — also abandons other live runs).

| Flag | Default | Effect |
|---|---|---|
| `--scope=<all\|all-non-skip\|high\|test>` | `all` | Profile selection: `all` = every bucket (~160), `all-non-skip` = drops `low_signal_skip_default` (~80), `high` = `high_signal_required` only (~37), `test` = first 3 of `high_signal_required`. Adaptive auto-select on subsequent runs per `SKILL.md` standing default #19. |
| `--cutoff=<ISO>` | from `seen-items.json` `current_meeting_window.opened_date`, else 14d ago | Override cutoff |
| `--anti-bot-cap=<N>` | 90 | Pause after N chrome navs in current session |
| `--with-replies-medium` | off | Run with_replies pass for `medium_signal` bucket too |
| `--no-replies` | off | Skip with_replies for ALL profiles |
| `--dry-run` | off | Synthesize/categorize agents return `[]` without spawning claude -p |
| `--force` | off | Abandon other `in_progress`/`paused` runs; mint new run |
| `--grok-preload` | off | Wave 0: probe Grok CLI; set `config.grok_preload` when ready (else `grok_degraded`) |
| `--grok-model=<slug>` | default | Optional Grok model for Wave 0 (`-m` on host `grok -p`) |
| `--require-grok` | off | Fail init when `--grok-preload` requested but probe not ready |

**stdout:** `{run_id, total, scope, cutoff, ordered_handles[], anti_bot, config, grok_degraded?}`

#### `grok-check`

Probe Grok Build install/auth on the host. Optional tooling — briefing never requires Grok.

**stdout:** `{ready, reason, bin, version, required_for_briefing: false, ...}`

#### `grok-capture --index=N [--resume=<run-id>]` — NOT YET WIRED

**Deferred:** this subcommand is documented and its library (`grok-capture-agent.js` / `grok-capture-spawn.js`) exists, but it is **not registered in the runner's `buildSubcommands()` dispatch in this release**, so invoking it returns "Unknown subcommand". A follow-up wires it. Until then, run without `--grok-preload`; Chrome Wave 1 is the full path. Intended behavior once wired:

Wave 0 — host headless `grok -p` X preload for one profile. Requires `init --grok-preload` with successful probe (`config.grok_preload: true`). When disabled or capture fails, records `S0_grok_capture: skipped` (non-blocking). Default spawn timeout: 300s (`DEFAULT_GROK_CAPTURE_TIMEOUT_MS` in `grok-capture-agent.js`). Output: `context/runs/<run-id>/grok-captures/<slug>.json` + `profile.grok_captures`. S3 merges with Chrome captures (Chrome URLs win on dedup).

**stdout:** `{handle, index, post_count, duration_ms, path?, skipped?, reason?, run_id}`

#### `next-handle [--resume=<run-id>]`

Returns the next pending profile or signals done/paused. Auto-resumes latest in-progress run if `--resume` omitted.

**stdout (next profile):** `{handle, index, priority_bucket, posts: {url, js}, replies: {url, js}|null, profile_path, cutoff, anti_bot, run_id, grok_preload?}` — `posts.js` ready for `mcp__claude-in-chrome__javascript_tool`; `posts.url` ready for `browser_batch` navigate action.

**stdout (run complete):** `{done: true, run_id, by_status}`

**stdout (anti-bot pause):** `{paused: true, reason: 'anti-bot-cap', anti_bot, run_id}` — exit 1.

#### `commit-s1 --index=N --captures=<file> [--resume=<run-id>]`

Reads JSON file `<{posts: <extractor-output>, replies: <extractor-output>|null}>`. zod-validates each via `validateExtractorOutput`. Writes S1+S2 stages to per-profile JSON. Bumps `master.anti_bot.navs_used`.

**stdout:** `{s2_passed, posts_count, replies_count, oldest_captured, cutoff_reached, navs_used, handle, run_id}`

#### `synthesize --index=N [--resume=<run-id>]`

Loads per-profile `raw_captures` + optional `grok_captures`; merges tweets (Chrome URLs win on dedup) before spawning `claude -p` (Sonnet) with synthesis prompt. zod-parses `[{title, summary, urls[], date (REQUIRED ISO YYYY-MM-DD), tierHint?, bucketHint?}]`. Writes S3 stage.

**stdout:** `{candidate_count, candidates, handle, s3_status, error?, run_id}`

#### `categorize --index=N [--resume=<run-id>]`

Loads `synthesized_candidates`. Spawns `claude -p` (Sonnet) with categorize prompt. zod-parses `[{..., bucket ∈ 9-bucket router, tier ∈ {HIGH,MED,LOW}}]`. Writes S4 stage.

**stdout:** `{categorized_count, dropped_apolitical, items, handle, s4_status, error?, run_id}`

#### `commit-and-checkoff --index=N [--resume=<run-id>]`

S5 — append categorized items to `seen-items.json` (URL-dedup), append profile section to `briefing-deltas.md`. S6 — set profile.status terminal, bump `master.current_index`, update `by_status`, append synthesis-log entry. Anti-bot check: if cap reached AND more profiles remain, set `master.status='paused'` and exit 1.

**stdout:** `{status, items_added, duplicates_dropped, current_index, total, paused, anti_bot, handle, run_id}`

#### `mark-failed --index=N --stage=<S1|S3|S4|orchestration> --error=<msg> [--resume=<run-id>]`

Records terminal failure for an explicitly-named stage. Bumps `current_index` and `by_status.failed`. Used when the main-session orchestrator can't recover from chrome MCP errors after retries.

**stdout:** `{status: 'failed', current_index, by_status, handle, run_id}`

#### `status [--resume=<run-id>]`

Read-only snapshot of `master.json`. Includes complete runs in latest-run resolution.

**stdout:** `{run_id, status, current_index, total, by_status, anti_bot, cutoff, scope}`

#### `summary [--resume=<run-id>]`

Re-scans every per-profile JSON to recompute `by_status`. Sets `master.status='complete'` if `current_index >= total`. Lists failed handles.

**stdout:** `{run_id, status, total, by_status, anti_bot, cutoff, scope, started_at, completed_at, failed_handles: [{handle, index, last_error}]}`. Exit 3 if `failed > 0`.

#### `retry-failed [--resume=<run-id>]`

Lists profiles with `status: failed`. Does NOT execute retries — the main session loops over the returned handles and re-invokes `commit-s1 → synthesize → categorize → commit-and-checkoff` fresh for each.

**stdout:** `{handles: [{handle, index, last_error}], total: N, run_id}`

#### `detect-resume`

Skill-entry helper. Returns the latest in_progress/paused run with progress fields, OR `{noActiveRun: true}`. No flags. The skill's Step 0.4 calls this before `init` to decide whether to resume / synthesize / scrap / abort.

**stdout (active run):** `{noActiveRun: false, run_id, status, current_index, total, by_status, anti_bot, cutoff, scope, started_at, next_handle, completed_handles[], items_added, deltas_lines, other_live_runs[]}`

**stdout (no active run):** `{noActiveRun: true}` (or `{noActiveRun: true, reason: 'no-runs-dir'}` if `context/runs/` doesn't exist yet).

`items_added` is the count of `###` headings in `briefing-deltas.md` (one per categorized item). `deltas_lines` is line count of the same file. Both 0 when file missing.

#### `abandon [--resume=<run-id>] [--reason=<msg>]`

Marks an in_progress/paused run as `abandoned` with optional reason. Frees the next `init` call to start a fresh run without `--force`. Refuses on already-complete runs.

**stdout:** `{run_id, status: 'abandoned', current_index, total}`

## Skill-entry resume policy

The skill's Step 0.4 (Resume detect) gates whether `init` runs at all. Decision tree:

```text
node per-profile-runner.js detect-resume
  ├── {noActiveRun: true}      → fall through to Step 0.5 (build checklist) + Step 0.7 (confirm) + init + Wave 1 loop
  └── {noActiveRun: false, ...} → AskUserQuestion: continue / synthesize / scrap / show-deltas / abort
       ├── continue   → if status==paused, resume-paused first; then jump straight to Wave 1 loop (skip checklist + confirm)
       ├── synthesize → summary (sets master.status=complete) + pipeline regen + emit briefing
       ├── scrap      → abandon --reason=<...> + fall through to Step 0.5 (init succeeds without --force)
       ├── show-deltas → cat briefing-deltas.md + re-ask
       └── abort      → exit, run state untouched
```

Auto-mode default (non-interactive) = continue if scope/cutoff match, else abort. Never auto-scrap.

## Subagent invocation contract (S3, S4)

`claude -p '<prompt>' --model claude-sonnet-4-6 --output-format json`

Runner builds the prompt → captures stdout → parses outer JSON wrapper → extracts `result` field → parses inner JSON → validates with zod (`CandidatesArraySchema` / `ItemsArraySchema`). On any step failure: 1× retry. Persistent failure → mark stage `partial`.

**Empirically verified working** without `--mcp-config` — these tasks are pure text in/out. ~2 burst requests per profile (S3 + S4).

## Chrome MCP — main-session orchestration

Node cannot call `mcp__claude-in-chrome__*`. The runner produces extractor data; the main CC session executes the chrome calls.

Per-profile sequence the main session executes between `next-handle` and `commit-s1`:

```text
1. Bash: node per-profile-runner.js next-handle
       → captures `result` JSON: {posts: {url, js}, replies?: {url, js}, ...}

2. mcp__claude-in-chrome__browser_batch
   - navigate result.posts.url
   - sleep 3000

3. mcp__claude-in-chrome__javascript_tool   (script = result.posts.js)
       → returns `{n, oldest, stable_iterations}` summary; full result stashed on window.__capPosts
       (Stash + chunked retrieval — MCP javascript_tool response is truncated
        at ~1500-2000 chars regardless of JS-side data size; see chrome-extraction.md
        "Chunked retrieval")

3a. Chunk-reader sub-loop (main session):
    for s in 0 .. summary.n step CHUNK_SIZE (default 4):
      mcp__claude-in-chrome__javascript_tool(buildChunkReaderJs('posts', s, s + CHUNK_SIZE))
        → returns JSON-stringified array of CHUNK_SIZE tweets (or fewer at tail)
    posts = assembleChunks(summary, chunks, {handle, surface: 'posts'})
        → full {a, n, oldest, stable_iterations, tw[]}, validated via validateExtractorOutput

4. (if result.replies)
   mcp__claude-in-chrome__browser_batch
     - navigate result.replies.url
     - sleep 3000
   mcp__claude-in-chrome__javascript_tool   (script = result.replies.js)
       → returns `{n, stable_iterations}` summary; full result stashed on window.__capReplies

4a. Chunk-reader sub-loop with surface='with_replies'
    replies = assembleChunks(summary, chunks, {handle, surface: 'with_replies'})

5. Write { posts: <step3a>, replies: <step4a>|null } to a tmp file

6. Bash: node per-profile-runner.js commit-s1 --index=N --captures=<tmpfile>
       → state advances S1 + S2
```

**Why chunked retrieval.** MCP `javascript_tool` truncates response payloads at ~1500-2000 chars even when the JS execution captured more data — empirically reproduced on @AnthropicAI with 13 tweets at 80-char text cap (tail-end data silently lost). The extractor templates stash full results on `window.__capPosts` / `window.__capReplies` and return only the summary; the main session reads `tw[]` in `CHUNK_SIZE`-tweet slices via separate `javascript_tool` calls. Chrome MCP calls do NOT count toward Claude burst budget (in-session tool calls), so the extra round-trips are free against rate limits. Helpers exported from `lib/chrome-extract.js`: `CHUNK_SIZE`, `buildChunkReaderJs(surface, start, end)`, `assembleChunks(summary, chunks, {handle, surface})`. Test coverage: `scripts/chunked-retrieval.test.js`.

Then `synthesize → categorize → commit-and-checkoff` are pure Bash invocations of the runner — no MCP needed.

**Cookie-filter fallback ladder:** when the `javascript_tool` result starts with `[BLOCKED: Cookie/query string data]`, the main session walks the `FALLBACK_LADDER` exported from `chrome-extract.js`:

| Tier | Tool | When |
|---|---|---|
| 1 | `javascript_tool` | default path |
| 2 | `get_page_text` | Tier 1 returned BLOCKED filter |
| 3 | `read_page` | Tier 2 still returned no usable data |
| 4 | `screenshot` | last-resort manual extraction; mark `fallback_tier` in synthetic output |

The main session decides per-profile whether to retry or escalate to `mark-failed`.

## Anti-bot pause / resume

Each chrome navigation is one count. `commit-s1` increments `master.anti_bot.navs_used` by 1 (posts only) or 2 (posts + with_replies). Cap default 90.

Pause flow:

1. `commit-and-checkoff` detects `navs_used >= cap` AND more profiles remain → sets `master.status = 'paused'`, exit 1.
2. Next invocation of any subcommand reads `master.status === 'paused'` → `next-handle` first emits `{paused: true, reason: 'anti-bot-cap'}` and exits 1, OR (if user re-invokes) the orchestration loop bumps `session_count`, resets `navs_used = 0`, sets `status = 'in_progress'`, and continues from `current_index`. (Reset is performed by the main session via a fresh `init --force` OR by patching the master via implicit resume in `next-handle` when a new session begins.)

Cross-session: re-running the orchestration loop is the resume — no new flags needed beyond optional `--resume=<run-id>`.

## State file layout

```text
${CLAUDE_PLUGIN_DATA}/<profile>/context/runs/<run-id>/
├── master.json                 # global progress + ordered queue + anti-bot
├── per-profile/
│   ├── 001-bcherny.json        # padded index, slug-safe handle (no @, lowercase)
│   ├── 002-_catwu.json
│   └── ...
├── synthesis-log.jsonl         # append-only per-profile timing + status audit
└── briefing-deltas.md          # incremental briefing markdown delta consumed by emit-slides-data.js
```

`<run-id>` = ISO basic timestamp (`20260506T103000Z`). Cross-platform safe (no colons).

## Atomic write pattern

`state.js` `atomicWriteJson` / `atomicWriteText`:

```javascript
import { promises as fs } from 'node:fs';
import { randomBytes } from 'node:crypto';
import path from 'node:path';

export async function atomicWriteJson(filePath, data) {
  const dir = path.dirname(filePath);
  await fs.mkdir(dir, { recursive: true });
  const tmpPath = path.join(dir, `.${path.basename(filePath)}.${randomBytes(4).toString('hex')}.tmp`);
  await fs.writeFile(tmpPath, JSON.stringify(data, null, 2), 'utf-8');
  await fs.rename(tmpPath, filePath);
}
```

Same pattern for the markdown delta log — append-only via `fs.appendFile` (rename atomicity not needed for incremental writes).

## Cost model (Option A)

For a full `--scope=all` run (~160 profiles):

- **Chrome MCP calls** (main session): 160 × ~1.3 ≈ 210 (with_replies fires for HIGH + LEADERSHIP buckets ≈ half-and-half mix). These don't count as separate burst requests — they're tool calls inside the active session.
- **`claude -p` subprocesses**: 160 × 2 (S3 + S4) = 320 burst requests. Plus ~10% retries → ~350.
- **Main session orchestration overhead**: ~50-100 messages worth of model thinking between subcommand invocations, depending on whether the session compacts mid-run.
- **Anti-bot session pacing**: 90-nav cap → ~210 navs needs ~2-3 sessions with manual re-trigger between. Wall-clock ~30-45 min per session.
- **Smaller scopes**: `--scope=all-non-skip` (~80 profiles, ~160 burst) or `--scope=high` (~37 profiles, ~75 burst) when adaptive logic demotes scope on tail-of-window runs.

Total ≈ 250-350 burst requests against the 5-hour window (materially relaxed post-2026-05-06 — see `.claude/rules/rate-limit-aware-workflow.md` "Current effective limits"). Stay under 50% of the burst cap as a comfort margin.

## Verification

From `scripts/`:

```bash
npm test
```

Runs all `*.test.js` files (unit tests first, then dry-run stage CLI integration tests). Live `claude -p` smoke cases inside `synthesize-categorize-contracts.test.js` require Claude CLI on PATH.

## Cross-references

- `per-profile-loop.md` — 6-stage state machine spec (this implements; KEEP unchanged body)
- `chrome-extraction.md` — posts + replies + selector probe extractor JS (exported as constants from `lib/chrome-extract.js`)
- `SKILL.md` Standing default #16 — tier table consumed by `categorize-agent.js`
- `SKILL.md` Standing default #18 — top-level pointer to per-profile-loop.md + this file
- `output/build/emit-slides-data.js` — reads `briefing-deltas.md` via sentinel-merge into the meeting markdown before slide emit
- `code.claude.com/docs/en/mcp-servers#plugin-provided-mcp-servers` — primary source on plugin MCP scope
- `code.claude.com/docs/en/cli-reference` — `--mcp-config` / `--strict-mcp-config` flags
