## Execution Flow

### Step 0: Parse arguments and load state

1. Parse `$ARGUMENTS` for flags (see table above)
2. Read `context/seen-items.json` — if missing, initialize empty: `{"last_run": null, "x_list_url": null, "meeting_n": 0, "items": [], "runs": []}`
3. If `--status`: display run count, total items, items per provider, last run date, last_following_refresh age, meeting_n. Stop.
4. If `--reset`: create fresh empty state (preserve `meeting_n`), confirm to user. **Do NOT write a `seen-items.backup.json` file** — git history is the rollback path.
5. **Determine time window via meeting-window state** — cutoff is anchored on the current meeting window, NOT the last run. Multiple runs between meetings share the same cutoff and accumulate findings into one output file. See `references/window-state.md` for the full cutoff determination logic + 30-day cap warning.

### Step 0.4: Resume detect (MANDATORY)

Before building the run checklist, check for an in-progress or paused run from a prior session. State persists across `/clear`.

```bash
node scripts/per-profile-runner.js detect-resume
```

On `{noActiveRun: true}` → fall through to Step 0.5. On `{noActiveRun: false, ...}` → surface to user via `AskUserQuestion` with 5 options (continue / synthesize / scrap / show-deltas / abort). See `references/resume-detect.md` for the full options panel, branch logic per option, and auto-mode policy (non-interactive defaults to **continue** if scope+cutoff match, else **abort** — never auto-scrap).

### Step 0.5: Build run checklist (MANDATORY)

Before any wave executes, build the authoritative coverage checklist. See `references/checklist-system.md` for full schema and logic.

1. Read `context/following-list.json` → `scan_priority` buckets
2. Build one row per profile across all four `scan_priority` buckets. Skip `low_signal_skip_default` only when `--skip-low-signal` set OR adaptive logic demotes scope
3. Build Wave 1.5 rows for high-volume accounts (when window >7d)
4. Build Wave 2 rows: 2 per provider (perplexity_ask + WebSearch)
5. Build Wave 3 rows: every RSS feed + every changelog + every GH repo from `providers.md`
6. Build Wave 4 rows if `--extras` enabled
7. Write to `context/runs/<run-id>-checklist.json` with `status: "pending"` for all rows
8. Display total row count to user

### Step 0.5b: Window state

The `current_meeting_window` field in `seen-items.json` tracks the active aggregation period. First run after window-closed opens a new window (auto-increments `meeting_n`, sets `opened_date`, computes 14-day `target_close_date`). Subsequent runs while window open share cutoff and append to same output file. `--meeting-prep` / `--close-meeting` closes the window and archives the output. See `references/window-state.md` for full schema + lifecycle table.

**Following-list freshness check:** read `context/following-list.json` `last_following_refresh`. If `(now - last_refresh) > 42 days`, prompt user to refresh. On `y` OR `--refresh-following`, run Step 0a before continuing.

### Step 0.6: Window-status / close-meeting short-circuit

- If `--window-status` flag → print `current_meeting_window` state + last 3 runs + items_added. Stop.
- If `--close-meeting` flag (no fresh briefing requested) → execute Step 7 close logic only. Stop.

### Step 0.7: Pre-execution confirmation (MANDATORY GATE)

**Before any wave runs**, present plan summary and await user confirmation. This is the contract — no surprise execution. See `references/pre-execution-gate.md` for the full panel format, response handling, and skip-confirmation conditions.

**Skip confirmation when:**

- `--yes` / `-y` flag set
- Non-interactive context detected (`CLAUDE_CODE_REMOTE=true`, `<<autonomous-loop>>` sentinel, `claude -p`) → auto-confirm with note in output header

### Step 0a: Refresh following list (when triggered)

Navigate to `x.com/{user}/following`, run `window.__seen` virtualized-list extractor (see `chrome-extraction.md`), diff against current `following-list.json`, surface missing/removed handles to user with proposed bucket assignments, write updated file with new `last_following_refresh` timestamp. ~2 min if list <200 accounts.

### Step 1: Load source registry

Read `references/providers.md` for the full provider account registry, query templates, and changelog URLs. The active profile's `following-list.json` is the authoritative handle registry; `providers.md` supplies the per-bucket query/changelog scaffolding.

### Step 2: Multi-wave collection

Run ALL four waves. Each wave produces candidate news items. Cross-reference across waves to increase confidence — items found by multiple waves get higher confidence scores.

**Wave 0: Grok preload (optional, `--grok-preload`)**

Optional enrichment before Chrome Wave 1. When Grok is not installed or not signed in, `init` sets `grok_preload: false` and returns `grok_degraded` (unless `--require-grok`). Per profile: `grok-capture --index=N` → skip with `skipped: true` (exit 0) → continue to Chrome S1. Probe anytime: `node scripts/per-profile-runner.js grok-check`.

When ready, headless `grok -p` uses native X search; output lands in `context/runs/<run-id>/grok-captures/` and `profile.grok_captures`. S3 synthesize merges Grok + Chrome tweets (Chrome URLs win on dedup). **Chrome Wave 1 remains the canonical path** for following-list refresh and ground-truth capture.

**Wave 1: Per-profile orchestration (canonical, main-session-driven Option A)**

This is the primary Twitter data source — free, authenticated, real browser context. Wave 1 is orchestrated by the main interactive Claude Code session: it drives chrome-in-chrome MCP directly (only the main session's WebSocket can reach the extension) and calls the runner's stage CLI between captures.

Per-profile loop: S1 Capture → S2 Validate → S3 Synthesize → S4 Categorize → S5 Persist → S6 Check off. Per-profile JSON written after every stage. Master file tracks `current_index`, `by_status` counts, anti-bot navs. Resume: re-run the orchestration loop. Anti-bot cap default 90 navs/session; commit-and-checkoff exits 1 when capped, main session pauses and waits for user re-trigger.

**See `references/per-profile-loop.md` "Wave 1 orchestration loop" for the exact tool-call sequence (init → next-handle loop → browser_batch + javascript_tool with chunked retrieval → commit-s1 → synthesize → categorize → commit-and-checkoff → summary), scope flag table, and fallback paths.**

**Wave 1.5: Twitter Advanced Search (high-volume accounts only, when window >7d)**

X profile-page Posts tab caps at ~7 days of content for high-volume posters. For windows >7d, follow up Wave 1 with Advanced Search pass on accounts in the high-volume set (see `references/providers.md`). For each account, navigate to:

```text
https://twitter.com/search?q=from%3A{handle}%20since%3A{cutoff_date}%20until%3A{run_date}&f=live
```

URL-encode date params. Use `f=live` for chronological order. Run the posts force-scroll extractor (same JS as Wave 1) on the search results page. Date filter is enforced by URL; no additional cutoff JS needed beyond dedup. Skip Wave 1.5 entirely when window ≤7d.

**Wave 2: Provider-specific Perplexity + WebSearch**

For each active provider category (filtered by `--providers` if set), run targeted queries using both Perplexity and WebSearch. This wave always runs regardless of chrome availability.

- **Perplexity queries** (one per provider, sequential — same MCP server): use `perplexity_ask` with `search_context_size: "high"` and `search_recency_filter` matching the timeframe. Include specific account handles for relevance. See `references/providers.md` for per-provider query templates.
- **WebSearch queries** (parallel-safe with Perplexity): `"[provider] AI announcements [timeframe] site:x.com"` for tweet-level coverage.

**Perplexity limitation:** indexes via Google/Bing, not Twitter directly. Treat results as discovery leads. Run multiple query phrasings and cross-reference with Wave 1 chrome data when available.

**Wave 3: RSS feeds + Changelog + GitHub releases (deterministic sources)**

- **RSS feeds first (preferred — dated, structured):** use `mcp__ref__ref_read_url` or `WebFetch` on RSS endpoints in `references/providers.md`. Parse `<item>` elements; filter by `pubDate >= cutoff_date`. RSS-failure fallback: HTML scrape via WebFetch on the parent blog URL.
- **Changelog pages (HTML — fallback when RSS unavailable):** Anthropic `code.claude.com/docs/en/changelog`, OpenAI `developers.openai.com/codex/changelog`, Google `ai.google.dev/gemini-api/docs/changelog`, Cursor `cursor.com/changelog`.
- **GitHub releases (parallel-safe):** one `gh api repos/{repo}/releases?per_page=10` call per repo in `providers.md`, filter `published_at >= cutoff_date` via jq. Repos: anthropics/claude-code, anthropics/anthropic-sdk-*, openai/openai-agents-*, openai/codex, google/generative-ai-*, oven-sh/bun, langchain-ai/*, microsoft/vscode, vercel/ai, firecrawl/firecrawl, etc.

**Wave 4: Broader AI landscape + EXTRAS**

Discovery queries to catch developments outside tracked providers:

- Perplexity: "Most significant AI product launches, model releases, and developer tool announcements in the last [timeframe], excluding Anthropic, OpenAI, Google, and Cursor"
- WebSearch: "AI developer tools announcements [timeframe]"

If `--extras` is set, also run: Perplexity: "Most interesting and unusual AI developments in the last [timeframe] — robotics, brain emulation, games using AI, science breakthroughs, novel applications."

### Step 3: Deduplicate

Before categorizing, deduplicate against `context/seen-items.json`:

1. Load existing items from state
2. For each newly collected item, normalize its URL:
   - Strip tracking params: `?utm_*`, `?ref=*`, `?s=*`, `?t=*`
   - Normalize domain: `twitter.com` → `x.com`
   - Remove trailing slashes
   - Lowercase the domain portion
3. Check if normalized URL exists in state
4. If exists: skip (already captured)
5. If new: include in output AND queue for state update

### Step 4: Categorize and rank

**13-bucket canonical schema** — every run produces a section per bucket (empty buckets get a "no notable items this window" line — never silently drop). Apolitical filter applied here, BEFORE ranking — strip partisan-only items per "Apolitical filter" rule above.

**Cross-cutting H2 sections** — author these AFTER the 13 provider buckets in `meeting-{N}.md`. Each is parsed by `lib/parse-briefing.js` and emitted by `lib/emit-slides.js` as a dedicated slide:

| Section | Purpose | Format |
|---|---|---|
| `## Dev Tools — Release Walk` | Per-tool chronological breakdown for engineering audience | H3 per tool (e.g. `### Claude Code (heavy use)`) with version-by-version bullets. Recognized tools: Claude Code, Cursor, Codex, GitHub Copilot, Augment Code (priority order from `references/providers.md` "Dev-tools priority list") |
| `## Patterns` | Cross-bucket synthesis (≥3 themes) | Bullet list under H2 — no H3 tiers. Each bullet `- **Theme**: 1-2 sentence body` |
| `## Pace` | Vendor velocity / cadence comparison | Bullet list under H2 — no H3 tiers. e.g. `- **Claude Code**: 10 releases (~1/day)` |
| `## Breaking & Deprecated` | Heads-up surface for removals, EOL, security advisories | Bullet list under H2. Items containing keywords from `providers.md` "Breaking & Deprecated keywords" auto-promote here |

When emit-slides finds these sections populated, it appends dedicated slides under the `news` parent group. Empty / missing sections are silently skipped.

Organize new items into the 13 provider categories named in standing default #11 (Anthropic / OpenAI / Google / Cursor / xAI-Grok / Meta-Llama / DeepSeek / Microsoft / Compute & Infrastructure / Real-world AI / Legal & regulatory / Other / EXTRAS). Per-provider topic scope detail: `references/providers.md`.

Within each category, rank by estimated impact:

- Model releases, major version announcements → HIGH
- New features, product launches → HIGH
- API changes, developer tools → MEDIUM
- Blog posts, thought leadership → MEDIUM
- Minor updates, patches → LOW

### Step 4.5: Enrichment passes

After base 13-bucket categorization, run enrichment passes BEFORE output finalized. Each pass mutates items in place. See `references/enrichment-passes.md` for full pass details:

- **Fact verification gate (HIGH items)** — WebFetch source URL, grep for claim, flag `[VERIFY]` + demote on mismatch
- **Stack-aware research lens (impact tag, profile-provided)** — when the active profile supplies a stack lens, per-item `impact: high|medium|low|none + 1-line reason`, rendered as italic tag below body; stack context from `references/audience-defaults.md`. Skipped with no profile lens
- **Sentiment / hype-discount filter** — strip superlatives at S3 synthesis; track per-provider marketing-tone ratio
- **"What's missing" check (negative space)** — cross-check captures against WebSearch/Perplexity major-releases query; flag `[CATCH-UP]` for missed items

### Step 5: Generate output

The output format depends on `--format`:

#### Markdown (default)

Generate the briefing in this format and display it in the conversation:

```markdown
# AI Briefing — [start_date] to [end_date]

*[N] new items across [M] providers. [X] items deduplicated from previous runs.*
*Collection: [waves used, e.g., "Chrome + Perplexity + WebSearch + Changelogs"]*

## Anthropic

- **[Title/Topic]**: [URL]
  [1-2 sentence factual description]

## OpenAI / Google / Cursor / xAI / Meta / DeepSeek / Microsoft / Compute / Real-world / Legal / Other
...(same shape per bucket — empty buckets get "no notable items this window")...

## EXTRAS
*(only if --extras)*
...

---

## Coverage Verification

- **Total rows:** [N] ([X] profiles + [Y] Adv Search + [Z] Wave 3 sources)
- **Complete / Partial / Skipped / Failed:** counts + one-line reason for non-complete
- Confirm: all high_signal_required profiles scanned to cutoff; all RSS feeds + changelogs + GH repos checked
- Run-checklist: `context/runs/<run-id>-checklist.json`

---
*Generated by /ai-briefing:ai-briefing | Last run: [timestamp] | Total tracked: [count] | Cutoff: [cutoff]*
```

**Primary output: `output/meetings/meeting-{N}.md`** — keyed by current `meeting_n`. **Each run rebuilds the body via merge** — load all items in `seen-items.json` belonging to the open window, group by provider, rank HIGH/MED/LOW, write a single clean document. **Never append a `## Run N` section, "Round 2 Addendum", "supplement", or "delta" subsection.** The reader sees one organized brief, not a stratigraphy of runs.

**Secondary outputs:**

- `output/meetings/latest.md` — copy of current `meeting-{N}.md` for quick access. Resync on every write.
- `output/meetings/archive/meeting-{N}.md` — moved here when window closes via `--meeting-prep` / `--close-meeting`.

**Anti-patterns — DO NOT produce:**

- `## Run N — <timestamp>` headings in the briefing body
- `## Round 2 Addendum`, `## Run N supplement`, `## Chrome scan deltas` subsections
- Any "items added since last run" section in the markdown — that's metadata, lives in `seen-items.json`
- `output/rolling.md` (predates meeting-window pattern)
- `context/seen-items.backup.json` (git is the rollback path)
- `context/seen-urls-set.json` (derivable from `seen-items.json`)

**`--add-only` mode** is now implicit — every run within an open window automatically merges. The flag is preserved as no-op for backward compatibility.

#### PPTX slides (`--format slides`) / HTML (`--format html`) / PDF

**Canonical pipeline:** in-tree `output/build/*.js` (Node ESM, pptxgenjs + playwright direct). Reproduces the deck deterministically from the active brand (brand tokens in `output/build/brand.js`).

**Summary flow:** emit `slides-data.js` from briefing markdown → AI overseer review of tier/headlines/Patterns synthesis → `node build-pptx.js && node build-html.js && node build-pdf.js` → `node validate.js` 6-gate audit → AI overseer review of `build/shots/slide-NN.png` + `audit.json` → ship gate. `node run.js` chains the mechanical steps when no pause needed.

**See `references/build-pipeline.md` "Slide/HTML/PDF generation (Step 5 detail)" for the full overseer-driven flow and slide structure list, and `references/slide-generation.md` "Fallback skill paths" for the fallback plugins (`/document-skills:pptx`, `/frontend-design:frontend-design`, `/ui-ux-pro-max:slides`) used only when the in-tree pipeline cannot run.**

### Step 6.5: Verify checklist (MANDATORY GATE)

Before declaring run complete, verify `context/runs/<run-id>-checklist.json`:

```python
summary = verify_checklist(cl)  # see checklist-system.md
cl['verification_summary'] = summary
cl['completed_at'] = now_iso
```

**Done-gate logic:**

- `summary['blocking_issues']` empty (all `complete` or `skipped`) → proceed to Step 7 output
- `summary['blocking_issues']` non-empty → present to user with retry / accept-partial / cancel options
- **Autonomous mode**: retry once with extended timeout, then accept-partial with auto-note. Log to verification_summary.
- **Interactive mode**: wait for user choice. Retry per-row, not whole pipeline.

Display final coverage: complete count, partial reasons, failed errors, skipped (low-signal) count. Confirm all high_signal_required profiles scanned to cutoff and all RSS feeds + changelogs + GH repos checked.

### Step 7: Update state

After successful output:

1. Append new items to `context/seen-items.json`. Per-item schema fields:
   - **Required** (set at S5 persist): `url`, `title`, `provider`, `source_type` (twitter|blog|changelog|github), `first_seen`, `confidence` (high|medium|low)
   - **Optional** (set at S4 categorize): `release_state` (research-preview|beta|public-beta|GA|deprecated), `cost_impact` (+$N/seat/month|-$N/MTok|rate_limit_doubled|unchanged|unknown), `segment_tags` (python|dotnet|frontend|cli|all), `category` (defaults to provider; `breaking-deprecated` overrides when keyword-matched)
   - **Incremented at S5 if URL exists:** `meetings_mentioned`, `update_history[]` (per-meeting summary entries)
   - **Populated post-meeting by `/ai-briefing:ai-briefing retro --meeting N`:** `audience_signal` (acted|noted|skipped)

2. Update `last_run` to current ISO timestamp
3. Append run metadata to `runs` array: `{date, timeframe, new_items, total_items, waves_used[], providers_checked[]}`
4. **Window-active run (no close flag):**
   - Append run record to `current_meeting_window['runs']`
   - Update `current_meeting_window['items_added']` cumulative count
   - Do NOT change `meeting_n` or `last_meeting_date`
   - `output/meetings/latest.md` updated to point to current `meeting-{N}.md`

5. **If `--meeting-prep` or `--close-meeting`:**
   - Set `current_meeting_window['status'] = 'closed'`
   - Set `current_meeting_window['actual_close_date'] = now`
   - Move `output/meetings/meeting-{N}.md` → `output/meetings/archive/meeting-{N}.md`
   - Append closed window to `meeting_history[]`
   - Set `state['last_meeting_date'] = today`
   - Set `state['meeting_n'] = current.meeting_n` (already incremented when window opened)
   - Set `state['current_meeting_window'] = null` (next run opens fresh)
   - Print `"Meeting #{N} window closed. Archived: output/meetings/archive/meeting-{N}.md"`

6. **If `--format slides` was passed (rare — explicit only):** generate slides from current `meeting-{N}.md`.

### Step 8: Pre/post meeting integration loop

Closes the briefing → meeting → retro → next-briefing loop:

```text
T-1 day (Thu evening)        /ai-briefing:ai-briefing review        Manual pre-meeting QA checklist (references/pre-meeting-qa-checklist.md)
T-0 (Fri 3pm meeting)        Present                    Audience reactions captured live
T+1 hour (post-meeting)      /ai-briefing:ai-briefing retro N       Record acted/noted/skipped per item; write retro-{N}.md
T+1 day (Sat)                Auto-tune                  Update following-list.json scroll/credibility from retro signals
T+7 days                     /ai-briefing:ai-briefing --since 7d    Mid-window check; adjust providers.md weights
T+14 days                    /ai-briefing:ai-briefing --meeting-prep  Next meeting prep cycle starts; close prior window
```

Each step's output feeds the next:

- Retro updates `audience_signal` → S4 enrichment uses signal to weight HIGH/MED/LOW for similar items in next window
- Drift report identifies handles to remove → next `--refresh-following` proposes drops
- "What's missing" gaps from one window become next-window priority sources

### Quality Rules

These exist because the primary value of the output is the SOURCE URLS — not AI-generated summaries. Users click through to the actual tweets/posts/blogs.

- Every item needs a source URL — no URL, no item
- Never fabricate tweet content. If Perplexity returns something uncertain, mark it `[UNVERIFIED]`
- Prefer direct sources (x.com post URLs, blog post URLs) over secondary coverage articles
- When multiple waves find the same item, note `(confirmed by N sources)` — this increases confidence
- Descriptions are factual and concise: 1-2 sentences max, no opinion or editorializing

### Error Handling

- **Chrome not available:** Skip Wave 1, note in output header. Waves 2-4 provide coverage
- **Perplexity timeout/failure:** Continue with WebSearch. Note the gap
- **WebFetch failure on changelog URL:** Skip, note it. Try WebSearch as fallback
- **`gh` CLI not available:** Skip GitHub releases, use WebFetch on release pages instead
- **No new items found:** Report "No new items since [date]" — never fabricate
- **seen-items.json corrupted:** Back up corrupted file, create fresh, warn user
- **Slide skill not installed:** Provide installation instructions, fall back to markdown output
- **Cookie/query-string filter `[BLOCKED]`:** Auto-fall-through to screenshot fallback (`computer scroll` + `get_page_text` + `screenshot`). Don't ask user.
- **MCP extension disconnect mid-batch:** Re-call `tabs_context_mcp` to verify tab still valid. Retry the failed batch. Cap recovery at 3 retries per profile.
- **X profile-page 7d scroll limit:** For windows >7d on high-volume accounts (sama, gdb, simonw, AnthropicAI, claudeai), follow up `/{user}` Posts pass with `/{user}/with_replies` pass. Falls back to Twitter Advanced Search if still missing content.
- **Browser batch timeout (3+ actions):** Cap at 2 profile-navigations per `browser_batch`. Stability tradeoff for completeness.
- **`window.__seen` virtualized list quirk:** Following/Followers/List pages remove DOM nodes as new ones load. Use `window.__seen = window.__seen || new Set()` to persist across multiple `javascript_tool` calls — see `chrome-extraction.md`.
