# Per-Profile Loop — 6-Stage State Machine

Canonical doc for the per-profile state machine that replaces wave-batched scanning. Each profile completes ALL 6 stages before the runner advances. State persisted after every stage. Resumable across sessions.

This doc supersedes the Wave 1 portion of `checklist-system.md`. Waves 1.5 / 2 / 3 / 4 still use the wave checklist.

## State machine

```
@handle → S1 Capture → S2 Validate → S3 Synthesize → S4 Categorize → S5 Persist → S6 Check off → next handle
              ↓             ↓              ↓               ↓
           retry 2×      retry 2×      retry 1×        retry 1×
              ↓             ↓              ↓               ↓
           failed        failed         partial         partial
```

Failed/partial profiles do NOT block run continuation. End-of-run summary lists them. `retry-failed` lists failed profiles; the main session reprocesses each through commit-s1 → synthesize → categorize → commit-and-checkoff.

## Stage table

| Stage | Owner | Acceptance criterion | Retry policy | Failure mode |
|---|---|---|---|---|
| **S0 Grok capture** | Runner (`grok -p`) | Wave 0 only when `init` enabled `grok_preload` (probe passed) | 0 | `skipped` (non-blocking); Chrome S1 continues |
| **S1 Capture** | Runner (deterministic) | Navigation OK + extractor returned without error (or fallback succeeded) | 2× extended-wait retries | `failed` after retries |
| **S2 Validate** | Runner (deterministic) | One of: `cutoff_reached === true` OR `oldest_captured` within 24h of cutoff OR `tweets_in_window === 0` AND `stable >= 3` | 2× re-extract with longer scroll | `failed` after retries |
| **S3 Synthesize** | AI subagent (Sonnet) | Returned valid JSON candidates array (≥0 items); every item has `{title, summary, urls[], date (REQUIRED, ISO YYYY-MM-DD), tierHint, bucketHint}` | 1× retry | `partial` (empty candidates) |
| **S4 Categorize** | AI subagent (Sonnet) | Every candidate has valid `bucket` ∈ {anthropic, openai, google, cursor, xai, meta, deepseek, other, extras} and `tier` ∈ {HIGH, MED, LOW} | 1× retry | `partial` (uncategorized items) |
| **S5 Persist** | Runner (deterministic) | Atomic seen-items append succeeded; URL set strictly grew or stayed same; briefing-deltas.md appended | 0 (atomic write) | abort entire profile (filesystem error) |
| **S6 Check off** | Runner (deterministic) | master.json `current_index++`, `by_status.complete++`; per-profile JSON `status: complete`; synthesis-log entry appended | 0 (atomic write) | abort entire profile |

## Stage details

### S1 Capture

**Posts** (every priority bucket): navigate `/{handle}` → wait 3s → run posts force-scroll extractor (`chrome-extraction.md` lines 69-111).

**With_replies** (mandatory for `high_signal_required` + `leadership_low_volume`; opt-in for `medium_signal` via `--with-replies-medium`): navigate `/{handle}/with_replies` → wait 3s → run replies extractor (`chrome-extraction.md` lines 346-388).

**Cookie-filter fallback ladder** (Tier 1-4 per `chrome-extraction.md` lines 195-205): javascript_tool → computer scroll + get_page_text → read_page → screenshot.

**Selector probe** (every 10 invocations): re-run the selector-presence probe (`chrome-extraction.md` lines 53-61) to detect X DOM rewrites mid-run.

**Per-profile JSON write after S1:**

```json
{
  "stages": {
    "S1_capture": {
      "status": "complete",
      "started_at": "2026-05-06T10:30:00Z",
      "completed_at": "2026-05-06T10:30:08Z",
      "posts_count": 7,
      "replies_count": 3,
      "fallback_tier": null,
      "selector_probe_ok": true
    }
  },
  "raw_captures": {
    "posts": [/* posts extractor output */],
    "replies": [/* replies extractor output */]
  }
}
```

### S2 Validate

Pure logic over `raw_captures`. No new I/O.

```
cutoff_reached = posts.some(p => new Date(p.d) < cutoff) || replies.some(r => new Date(r.d) < cutoff)
oldest_captured = min(...posts.map(p => p.d), ...replies.map(r => r.d))
within_24h = (cutoff - oldest_captured) <= 24h
empty_and_stable = (posts.length === 0 && replies.length === 0 && S1.stable_iterations >= 3)

S2_pass = cutoff_reached || within_24h || empty_and_stable
```

### S3 Synthesize

Subagent input: `{handle, priorityBucket, posts, replies, seenUrls, tierTable}`.

Subagent output (zod-validated): `[{title, summary, urls[], date, tierHint, bucketHint}]`. `date` REQUIRED, ISO YYYY-MM-DD = newest tweet's date in the candidate group. Candidates without a date are dropped (zod regex rejects).

Subagent prompt skeleton:

```
You are condensing raw Twitter/X captures for @{handle} into briefing candidates.

Inputs:
- {N} Posts since {cutoff}
- {M} with_replies since {cutoff}
- seen-items URL set ({K} URLs already covered in prior runs)
- Tier table (Standing default #16 from SKILL.md)

Output 0-K candidate briefing items as JSON array. Drop near-duplicates of seen-items.
Each item: {title, summary, urls, date (REQUIRED ISO YYYY-MM-DD), tierHint, bucketHint}.
Apolitical filter applied here — drop partisan-only items per SKILL.md "Apolitical filter".
```

### S4 Categorize

Subagent input: `[candidate, ...]` from S3.

Subagent output (zod-validated): `[{title, summary, urls, bucket, tier}]`.

Apolitical filter applied first (drop partisan-only). Then tier rule per Standing default #16. Then bucket router (9-bucket: anthropic / openai / google / cursor / xai / meta / deepseek / other / extras).

### S5 Persist

Atomic append-then-rename:

1. `seen-items.json` — for each S4 item not already in URL set, append `{url, title, provider, source_type, first_seen, confidence}` and add normalized URL to set.
2. `context/runs/<run-id>/briefing-deltas.md` — append profile section in canonical format:

```markdown
## @{handle} ({priorityBucket}) — {N} item(s)

### {bucket} [{tier}] — {title}
{summary}
URLs: {url1}, {url2}
Date: {date}

### ...
```

### S6 Check off

Atomic update of `master.json`:

1. `current_index += 1`
2. `by_status[status] += 1` (complete | partial | failed)
3. `anti_bot.navs_used += 1` (or `+=2` if with_replies fired)
4. Append `synthesis-log.jsonl` entry: `{handle, stage_durations_ms, items_added, status, ts}`
5. Per-profile JSON `status` set to terminal value.

## Execution protocol — main-session orchestration loop (Option A)

The runner is a stage CLI; the main interactive Claude Code session is the orchestrator. It calls subcommands via `Bash`, fires chrome MCP calls inline, spawns `claude -p` for S3/S4 via the runner. Plugin MCP scope research (`runner-architecture.md` "Why Option A") forced this split.

Pseudocode for the main session (one full `--scope=all` run):

```text
# 0. Init
Bash: node scripts/per-profile-runner.js init --scope=all --cutoff=<ISO>
# stdout → {run_id, total, ordered_handles[], ...}

# 1. Per-profile loop
loop:
  Bash: node scripts/per-profile-runner.js next-handle
  parse stdout JSON:
    if {done: true}              → break loop
    if {paused: true, reason}    → STOP and report; user re-runs the loop later
    else {handle, index, posts: {url, js}, replies: {url, js}|null, grok_preload?, ...}

  # S0 Grok capture (optional — when init enabled grok_preload)
  if grok_preload from next-handle OR init config:
    Bash: node scripts/per-profile-runner.js grok-capture --index=N
    # skipped: true → non-blocking; continue to Chrome S1

  # S1 Capture — MAIN SESSION drives chrome MCP
  mcp__claude-in-chrome__browser_batch:
    - navigate posts.url
    - sleep 3000
  posts_result = mcp__claude-in-chrome__javascript_tool(posts.js)

  if replies present:
    mcp__claude-in-chrome__browser_batch:
      - navigate replies.url
      - sleep 3000
    replies_result = mcp__claude-in-chrome__javascript_tool(replies.js)

  # Cookie-filter fallback (Tier 1→2→3→4 per chrome-extract.js FALLBACK_LADDER)
  if posts_result starts with "[BLOCKED: Cookie/query string data]":
    walk ladder; if all tiers exhaust → mark failed:
      Bash: node ... mark-failed --index=N --stage=S1 --error=<msg>
      continue loop

  # Write tmp captures file
  Write tmp/chrome-result-<index>.json with {posts: <result>, replies: <result>|null}

  # S2 + S1 commit
  Bash: node ... commit-s1 --index=N --captures=tmp/chrome-result-<index>.json

  # S3 Synthesize (claude -p subprocess inside runner — no MCP needed)
  Bash: node ... synthesize --index=N

  # S4 Categorize (claude -p subprocess inside runner)
  Bash: node ... categorize --index=N

  # S5 Persist + S6 Check off + anti-bot pause check
  Bash: node ... commit-and-checkoff --index=N
  parse stdout: if {paused: true} → STOP and report

  # Anti-bot pacing
  sleep 2-5s (random) before next iteration

  # Periodic selector-presence probe (every 10 profiles)
  every 10th profile (and at session start):
    mcp__claude-in-chrome__browser_batch (navigate to @AnthropicAI + sleep 3000)
    mcp__claude-in-chrome__javascript_tool(SELECTOR_PROBE)
    if !ok: ABORT + escalate to user

# 2. End-of-run
Bash: node scripts/per-profile-runner.js summary
# stdout → {status, by_status, failed_handles, ...}

# 3. Optional retry pass
Bash: node ... retry-failed
parse handles[]; loop those indices through commit-s1 → synthesize → categorize → commit-and-checkoff
```

The main session interprets `next-handle` JSON to decide its next move; the runner does NOT spawn chrome calls itself.

## Resume protocol

The runner is stateless between invocations — every subcommand reads `master.json` fresh. Resume is implicit: rerun the orchestration loop (or `next-handle` directly), which auto-resolves the latest in-progress / paused run.

| Master `status` | What happens on next invocation |
|---|---|
| `in_progress` | `next-handle` returns the next pending profile |
| `paused` | `next-handle` returns `{paused: true}` until session is reset; main session bumps `session_count`, resets `navs_used = 0`, sets status back to `in_progress` (typically by simply re-invoking the orchestration loop after the user signals "continue") |
| `complete` | `next-handle` returns `{done: true}`; `summary` exits 0 (or 3 if any failed) |
| `aborted` | Requires explicit `--resume=<run-id>` on every subcommand to continue |

For pinpoint resume of a specific run, every subcommand accepts `--resume=<run-id>` to bypass the latest-run heuristic.

## Init protocol (fresh run)

`node per-profile-runner.js init [flags]` — see `runner-architecture.md` "Subcommands" (init) for the canonical signature. Builds `ordered_handles` from `following-list.json` priority buckets in order: `high_signal_required` → `leadership_low_volume` → `medium_signal` → (`low_signal_skip_default` only if `--scope=all`). Resolves cutoff from `--cutoff` or `seen-items.json.current_meeting_window.opened_date` or 14d-ago fallback. Writes `master.json` with `status: 'in_progress'`.

## Anti-bot pause/resume

Each chrome navigation is one count. `commit-s1` increments `master.anti_bot.navs_used` (1 for posts, 2 if with_replies fires). Cap default 90.

Pause:

1. `commit-and-checkoff` detects `navs_used >= cap` AND more profiles remain → sets `master.status = 'paused'`, exit 1.
2. Main session sees `paused: true` in stdout → STOPs the loop and reports to user.

Resume (next session):

1. Main session re-invokes the orchestration loop.
2. First `next-handle` either returns `{paused: true}` (signaling user to confirm continuation) OR — if the main session orchestrator chooses — implicit-resumes by patching `master.status: 'in_progress'`, `navs_used: 0`, `session_count += 1` and proceeding from `current_index`.

User-visible: re-run the orchestration loop until `summary.status === 'complete'`.

## End-of-run

When `current_index >= ordered_handles.length`:

1. `master.json` `status: complete`, `completed_at: <iso>`.
2. Print summary table:

```
═══ Run summary ═══
Run-id:    20260506T103000Z
Total:     137 profiles
Complete:  130 (94.9%)
Partial:   5
Failed:    2
Sessions:  3 (anti-bot pauses)
Items:     287 candidates synthesized → 254 categorized → 198 added to seen-items (56 dupes)

Failed profiles:
  - @nonexistent-12345 — handle 404
  - @ClaudeCodeLog — cookie filter, all 4 fallback tiers exhausted

Call `retry-failed`, then reprocess each returned handle through commit-s1 → synthesize → categorize → commit-and-checkoff.
```

1. Exit code: 0 (all complete) | 3 (partial-with-failures).

## Failure modes

| Failure | Stage | Behavior |
|---|---|---|
| Chrome MCP disconnect | S1 | Re-call `tabs_context_mcp`, retry batch. Cap 3 reconnects per profile then `failed`. |
| `[BLOCKED: Cookie/query string data]` | S1 | Tier 1→2→3→4 fallback ladder. Final `failed` if all tiers exhaust. |
| Profile 404 / private | S1 | `failed` immediately. |
| `claude -p` non-zero exit | S3, S4 | 1× retry. Then `partial` with reason in error log. |
| zod schema mismatch on subagent output | S3, S4 | Retry once with stricter "must return valid JSON" prompt. Then `partial`. |
| Filesystem write error | S5, S6 | Abort entire profile, mark `failed`, continue with next. |
| Anti-bot cap hit mid-stage | any | Complete current profile through S6 if possible, then pause. |

## Schemas

### `master.json`

```json
{
  "run_id": "20260506T103000Z",
  "status": "in_progress | paused | complete | aborted",
  "started_at": "2026-05-06T10:30:00Z",
  "completed_at": null,
  "cutoff": "2026-04-24T19:00:00Z",
  "scope": "all | all-non-skip | high | test | resume",
  "current_index": 42,
  "ordered_handles": ["@bcherny", "@_catwu", "..."],
  "by_status": {
    "complete": 40,
    "partial": 1,
    "failed": 1,
    "pending": 95
  },
  "anti_bot": {
    "navs_used": 78,
    "cap": 90,
    "session_count": 1,
    "paused_at": null
  },
  "config": {
    "with_replies_medium": false,
    "selector_probe_interval": 10,
    "retry_s1_s2": 2,
    "retry_s3_s4": 1,
    "delay_min_ms": 2000,
    "delay_max_ms": 5000
  }
}
```

### `per-profile/<NNN>-<handle>.json`

```json
{
  "handle": "@bcherny",
  "index": 1,
  "priority_bucket": "high_signal_required",
  "status": "complete | partial | failed | in_progress | pending",
  "stages": {
    "S1_capture": {
      "status": "complete",
      "started_at": "...",
      "completed_at": "...",
      "posts_count": 7,
      "replies_count": 3,
      "fallback_tier": null,
      "retry_count": 0
    },
    "S2_validate": {
      "status": "complete",
      "cutoff_reached": true,
      "oldest_captured": "2026-04-25T08:00:00Z",
      "tweets_in_window": 10
    },
    "S3_synthesize": {
      "status": "complete",
      "candidate_count": 4,
      "subagent_duration_ms": 8200,
      "retry_count": 0
    },
    "S4_categorize": {
      "status": "complete",
      "categorized_count": 4,
      "dropped_apolitical": 0,
      "subagent_duration_ms": 5100
    },
    "S5_persist": {
      "status": "complete",
      "items_added": 3,
      "duplicates_dropped": 1
    },
    "S6_checkoff": {
      "status": "complete"
    }
  },
  "raw_captures": {
    "posts": [/* posts extractor output */],
    "replies": [/* replies extractor output, optional */]
  },
  "synthesized_candidates": [/* S3 output */],
  "categorized_items": [/* S4 output */],
  "errors": []
}
```

### `synthesis-log.jsonl` (append-only)

```json
{"ts":"2026-05-06T10:30:08Z","handle":"@bcherny","status":"complete","s1_ms":3200,"s2_ms":4,"s3_ms":8200,"s4_ms":5100,"s5_ms":15,"s6_ms":3,"items_added":3}
{"ts":"2026-05-06T10:30:14Z","handle":"@_catwu","status":"complete","s1_ms":2800,"s2_ms":3,"s3_ms":7900,"s4_ms":4800,"s5_ms":12,"s6_ms":2,"items_added":1}
```

### `briefing-deltas.md` (append-only)

Per-profile sections in canonical 9-bucket markdown. Appended in profile-completion order. Reader can grep by `## @<handle>` to find a specific profile.

## Cross-references

- `chrome-extraction.md` — posts + replies extractor JS (S1 building blocks)
- `runner-architecture.md` — Node runner module boundaries + CLI
- `checklist-system.md` — superseded for Wave 1 only; still authoritative for Wave 1.5/2/3/4
- `SKILL.md` Standing default #16 — tier table consumed by S4
- `SKILL.md` Standing default #18 — top-level pointer to this doc
- `../SKILL.md` "Apolitical filter" — applied at S3 synthesis + S4 categorize

---

## Wave 1 orchestration loop (main session — exact tool calls)

The Wave 1 loop is orchestrated by the main interactive CC session (not the runner). The runner exposes a stage CLI; the main session drives chrome-in-chrome MCP directly (only the main session's WebSocket reaches the extension).

**Why main-session orchestration, not autonomous runner:** plugin-defined MCP servers (claude-in-chrome) do NOT load in `claude -p` subprocesses (per [code.claude.com/docs/en/mcp-servers#plugin-provided-mcp-servers](https://code.claude.com/docs/en/mcp-servers#plugin-provided-mcp-servers) + [code.claude.com/docs/en/cli-reference](https://code.claude.com/docs/en/cli-reference)). Stages S3 (synthesize) + S4 (categorize) still spawn `claude -p` subprocesses inside the runner — pure text in/out, no MCP needed, empirically working.

The extractor JS stashes its full result on `window.__capPosts` / `window.__capReplies` and returns only a small summary because MCP `javascript_tool` truncates responses at ~1500-2000 chars (see `chrome-extraction.md` "Chunked retrieval"). The main session reads `tw[]` in `CHUNK_SIZE`-tweet slices via `buildChunkReaderJs` and reassembles via `assembleChunks` before `commit-s1`. Chrome MCP calls don't count against Claude burst budget — the extra chunk reads are free against rate limits.

### Exact orchestration sequence

```text
1. Bash: node scripts/per-profile-runner.js init --scope=<adaptive|all|all-non-skip|high|test> --cutoff=<ISO>
   (scope omitted → adaptive logic per SKILL.md standing default #19; first run in window = `all`)

2. Import helpers from lib/chrome-extract.js (or shell out via node -e):
     CHUNK_SIZE                          # default 4
     buildChunkReaderJs(surface, s, e)   # → JS string for javascript_tool
     assembleChunks(summary, chunks, {handle, surface})  # → full extractor shape, zod-validated

3. Loop:
     Bash: node scripts/per-profile-runner.js next-handle
       → JSON: {handle, index, posts:{url,js}, replies:{url,js}|null, ...}

     if {paused}: STOP — report "Run paused at K/N. Re-run skill to continue." and exit
     if {done}:   break loop

     # S0 Grok capture (optional — when init enabled grok_preload)
     if next-handle JSON has grok_preload: true:
       Bash: node scripts/per-profile-runner.js grok-capture --index=K
       # skipped: true → non-blocking; continue to Chrome S1

     # --- Posts surface (stash + chunked retrieval) ---
     mcp__claude-in-chrome__browser_batch
       - navigate posts.url
       - sleep 3000
     posts_summary_json = mcp__claude-in-chrome__javascript_tool(posts.js)
       → "{n: N, oldest: '...', stable_iterations: K}"   (full result stashed on window.__capPosts)

     # Cookie-filter fallback (FALLBACK_LADDER tier 1→2→3→4)
     if posts_summary_json starts with "[BLOCKED: Cookie/query string data]":
       walk ladder; on exhaust → Bash: node ... mark-failed --index=N --stage=S1; continue

     posts_summary = JSON.parse(posts_summary_json)
     posts_chunks = []
     for s = 0; s < posts_summary.n; s += CHUNK_SIZE:
       chunk_json = mcp__claude-in-chrome__javascript_tool(buildChunkReaderJs('posts', s, s + CHUNK_SIZE))
       posts_chunks.push(chunk_json)
     posts = assembleChunks(posts_summary, posts_chunks, {handle, surface: 'posts'})

     # --- with_replies surface (same pattern, stash key __capReplies) ---
     if replies present:
       mcp__claude-in-chrome__browser_batch
         - navigate replies.url
         - sleep 3000
       replies_summary_json = mcp__claude-in-chrome__javascript_tool(replies.js)
       replies_summary = JSON.parse(replies_summary_json)
       replies_chunks = []
       for s = 0; s < replies_summary.n; s += CHUNK_SIZE:
         chunk_json = mcp__claude-in-chrome__javascript_tool(buildChunkReaderJs('with_replies', s, s + CHUNK_SIZE))
         replies_chunks.push(chunk_json)
       replies = assembleChunks(replies_summary, replies_chunks, {handle, surface: 'with_replies'})
     else:
       replies = null

     Write tmp file chrome-result-<idx>.json with {posts, replies}

     Bash: node ... commit-s1 --index=K --captures=tmp/chrome-result-<idx>.json
     Bash: node ... synthesize --index=K
     Bash: node ... categorize --index=K
     Bash: node ... commit-and-checkoff --index=K
     if {paused}: STOP

     Random 2-5s delay before next iteration

     # Every 10 profiles: re-run SELECTOR_PROBE on @AnthropicAI; if !ok, abort + escalate

4. Bash: node scripts/per-profile-runner.js summary
     → {status, by_status, failed_handles}

5. (optional retry pass) Bash: node ... retry-failed → handles[]
   Loop those indices through commit-s1 + synthesize + categorize + commit-and-checkoff
```

### Scope flags (passed to `init`)

| Scope | Profiles | Use |
|---|---|---|
| `--scope=all` (default — first run in window) | ~160 | Full cold-start baseline across every `scan_priority` bucket |
| `--scope=all-non-skip` | ~80 (HIGH + MED + LEADERSHIP) | Adaptive auto-select after 2 quiet LOW runs, OR explicit opt-out via `--skip-low-signal` |
| `--scope=high` | ~37 | Tail-of-window pass when MED+LOW have gone quiet |
| `--scope=test` | 3 | First 3 high-signal handles — dry-run validation |

Scope auto-picks from `current_meeting_window.runs[]` velocity unless explicit (SKILL.md standing default #19). Relevance filter applied downstream at S4 categorize — `--scope=all` ≠ everything ships to briefing; low-bucket items still pass through ranking + apolitical + tooling-first heuristics.

`init --dry-run` makes synthesize/categorize return `[]` without spawning claude — exercises state schema end-to-end.

### Legacy summary

Covered by S1 internals: navigate to `/{handle}` → 3s wait → posts force-scroll until cutoff → for high+leadership buckets also navigate `/{handle}/with_replies` → replies extractor → return structured items per stage.

### When chrome is unavailable

If claude-in-chrome tools aren't accessible (Chrome not open, extension not connected), skip Wave 1 entirely and note in output header. Waves 2-4 still provide coverage — Wave 1 is the best source but not the only one.

### First run

If `x_list_url` is null in state, ask the user for their X List URL. If they don't have one, suggest creating a list with the accounts from `providers.md` and provide the handles. Store the URL in `seen-items.json` for future runs.

### Following list maintenance

Read `context/following-list.json` for the categorized account list with **scan_priority** buckets (`high_signal_required`, `medium_signal`, `low_signal_skip_default`, `leadership_low_volume`). Default scanning INCLUDES every bucket (first run = `--scope=all`); adaptive logic may demote scope on subsequent runs per SKILL.md standing default #19. Pass `--skip-low-signal` to force-drop the LOW bucket. Run `--refresh-following` to re-scrape `x.com/{user}/following` when new accounts are added.
