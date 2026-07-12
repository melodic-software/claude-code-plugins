# Chrome-Based Twitter/X Extraction Workflow

Extractor JS templates live as exported constants in `scripts/lib/chrome-extract.js` (`POSTS_EXTRACTOR_TEMPLATE` for `/{handle}`, `REPLIES_EXTRACTOR_TEMPLATE` for `/{handle}/with_replies`, `SELECTOR_PROBE` for session preflight). The main interactive Claude Code session feeds these to chrome MCP via `buildExtractorJs({handle, surface, cutoffIso})` → `{js, url}`. Plugin-defined MCP servers (claude-in-chrome) cannot run inside `claude -p` subprocesses ([primary source](https://code.claude.com/docs/en/mcp-servers#plugin-provided-mcp-servers)), which is why S1 capture stays in the main session. Orchestration (per-profile 6-stage loop, state writes, retries, anti-bot pause/resume, FALLBACK_LADDER) is split between the main session (drives chrome MCP) and `scripts/per-profile-runner.js` stage CLI (state machinery + S3/S4 `claude -p` subagents). See `runner-architecture.md` for the canonical Option A architecture and `per-profile-loop.md` for the 6-stage state machine + Execution protocol pseudocode. The runner writes per-profile JSON after every stage.

Step-by-step process for using claude-in-chrome to browse authenticated Twitter/X and extract tweet data. **5-surface coverage** model (Profile Posts + Profile with_replies + Home Following + Home For you + Twitter Advanced Search).

## Coverage matrix (5 surfaces)

| # | Surface | URL | When | Cap |
|---|---|---|---|---|
| 1 | **Profile Posts** | `/{handle}` | Always for `high_signal_required` + `medium_signal` + `leadership_low_volume` | 12 scrolls |
| 2 | **Profile with_replies** | `/{handle}/with_replies` | **Mandatory** for `high_signal_required`; opt-in for `medium_signal` via `--with-replies-medium` flag | 16 scrolls |
| 3 | **Home Following** (chronological) | `/home` + DOM-click `Following` tab + `⋯` → `Most Recent` | Once per run | 8 scrolls |
| 4 | **Home For you** (algorithmic) | `/home` (default) | Once per run, supplementary | 6 scrolls |
| 5 | **Twitter Advanced Search** | `search?q=from:..+since:..+until:..&f=live` | Window >7d on high-volume handles | per chunk-by-week, no pagination |

**Surface 2 (with_replies) is the canonical answer to feature-drop scoops missed by the Posts tab** — Posts collapses self-reply threads to "first tweet only", so a launch announcement that replies with details/screenshots gets truncated. with_replies surfaces every tweet in a thread.

## Why chrome is the primary Twitter source

- No API costs ($0) — official X API starts at $100/mo for read access
- Real browser session — lower anti-bot detection risk than headless automation
- Authenticated access — sees same content user would see manually
- Per-profile scanning captures content that Perplexity/WebSearch completely miss

## Approach: Per-Profile (Surfaces 1+2) + Home Feeds (Surfaces 3+4) + Advanced Search (Surface 5)

**Profile passes (Surfaces 1+2) are PRIMARY signal source.** Validated across multiple sessions:

- 60-67 profiles scanned individually
- 120+ tweets extracted that Perplexity missed entirely
- Key finds (auto-fix, iMessage channel, Codex plugins, worktree usage, CC ultrareview headless command, Cursor Security Review GA) came exclusively from per-profile chrome scanning

**The with_replies pass (Surface 2) catches feature-drop scoops** that Posts tab collapses to first-tweet-of-thread. Mandatory on `high_signal_required` handles. Examples missed by Posts-only: Blender plugin for Claude Code (likely posted as self-reply detail), small CC/Cursor feature drops where the launch tweet is a thread.

**Home feeds (Surfaces 3+4) augment** with retweets-of-importance + algorithmic surfacing. Two X-platform changes affect these:

1. **Following-tab default sort flipped to Grok-ranked** as of 2025-11-27 (Musk announcement) — must explicitly toggle to `Most Recent` via `⋯` menu to get chronological. Web UI still exposes the toggle; mobile app v11.65+ removed it.
2. **Tab-persistence bug since Dec 2025**: desktop X reverts to `For you` on every navigation. No URL parameter forces the tab; must DOM-click. Reference Chrome extension `mustafaer/twitter-default-following-tab` documents the position-based DOM-click pattern.

See "Home feed extraction (Surfaces 3+4)" below for the force-click sequence.

Account list: `context/following-list.json`, categorized by provider and **scan_priority** (high_signal_required / medium_signal / low_signal_skip_default / leadership_low_volume).

## Prerequisites

- claude-in-chrome extension installed and connected
- User logged into x.com in Chrome
- Chrome tab group available (use `tabs_context_mcp` with `createIfEmpty: true`)

## Session preflight — selector-presence probe

Before bulk extraction, run this probe on the first profile page (e.g. `@AnthropicAI`) to confirm X DOM hasn't been rewritten. Selectors verified stable across 2024-2026 (Scrapfly, ScrapingBee, LiveProxies guides) but X rolls defensive changes every 2-4 weeks.

```javascript
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await sleep(2500);
  const tweetCount = document.querySelectorAll('[data-testid="tweetText"]').length;
  const articleCount = document.querySelectorAll('article[data-testid="tweet"]').length;
  return JSON.stringify({tweetCount, articleCount, ok: tweetCount > 0 || articleCount > 0});
})()
```

If `ok: false` on a known-active profile, abort + escalate. Selectors in the extractor templates below assume `ok: true`.

## Posts surface extractor — force-scroll until cutoff

Force-scrolls until: (a) cutoff date reached, (b) stable scroll height for 3+ iterations, OR (c) max iterations hit. Captures full date range, not just first viewport.

Dedup uses a content-hashed key (`url + first 60 chars of text`), not URL alone, because quote-tweets render the quoted card *inside* the same `article` as the quoter's tweet — both `[data-testid="tweetText"]` nodes resolve to the same `/status/` URL via `.closest('article')`, so URL-only dedup silently drops quoted card text. The composite key keeps both records.

```javascript
(async () => {
  const cutoff = new Date('{cutoff_iso}');
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const seen = new Set();
  const results = [];
  let stable = 0;
  let oldest = new Date();

  for (let i = 0; i < 12; i++) {
    const tweets = document.querySelectorAll('[data-testid="tweetText"]');
    let newC = 0;
    tweets.forEach(tw => {
      const art = tw.closest('article');
      if (!art) return;
      const sl = art.querySelectorAll('a[href*="/status/"]');
      const url = sl.length > 0 ? 'https://x.com' + sl[0].getAttribute('href') : '';
      const t = art.querySelector('time');
      if (!t) return;
      const ts = new Date(t.getAttribute('datetime'));
      if (ts < cutoff) return;
      const txt = tw.textContent.replace(/\n/g, ' ').trim().substring(0, 200);
      const dedupKey = url + '::' + txt.substring(0, 60);
      if (seen.has(dedupKey)) return;
      seen.add(dedupKey);
      results.push({t: txt, u: url, d: t.getAttribute('datetime').substring(0, 16)});
      newC++;
      if (ts < oldest) oldest = ts;
    });

    let past = false;
    document.querySelectorAll('article time').forEach(t => {
      if (new Date(t.getAttribute('datetime')) < cutoff) past = true;
    });
    if (past && i >= 2) break;
    if (newC === 0) stable++; else stable = 0;
    if (stable >= 3) break;

    window.scrollBy(0, window.innerHeight * 2);
    await sleep(1300);
  }
  return JSON.stringify({a: '@{handle}', n: results.length, oldest: oldest.toISOString().substring(0, 16), tw: results});
})()
```

Replace `{cutoff_iso}` (e.g. `2026-04-24T00:00:00Z`) and `{handle}` (without @).

Force-scroll loop scrolls 12 times max, breaks on cutoff hit OR stable height. `if (past && i >= 2) break` guarantees minimum 1 scroll before early-exit (catches profiles where first viewport already has cutoff-old content). `stable >= 3` exit means three scrolls with no new tweets = end of feed reached. `newC` counter distinguishes "no new tweets this scroll" from "we already saw all of them". `oldest` tracking returns earliest timestamp captured, useful for verifying coverage.

The actual exported template (in `scripts/lib/chrome-extract.js`) additionally captures four optional fields per tweet — see "Tweet schema" below.

## Window-stored Set for virtualized lists (Following list extraction)

X's Following / Followers / List pages **virtualize** — old DOM nodes removed as new ones load. A local `Set` inside one JS call only sees current viewport. Workaround: store dedup Set on `window` so it persists across multiple `javascript_tool` calls.

```javascript
// Pass 1 — initialize + first scroll batch
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  window.__seen = window.__seen || new Set();
  const collect = () => {
    document.querySelectorAll('[data-testid="UserCell"]').forEach(cell => {
      cell.querySelectorAll('a[href^="/"]').forEach(a => {
        const h = a.getAttribute('href');
        if (/^\/[A-Za-z0-9_]{1,15}$/.test(h)) window.__seen.add(h.substring(1));
      });
    });
  };
  let lastH = 0; let stable = 0;
  for (let i = 0; i < 60; i++) {
    collect();
    window.scrollBy(0, 1500);
    await sleep(900);
    const h = document.body.scrollHeight;
    if (h === lastH && i > 2) stable++; else stable = 0;
    if (stable >= 4) break;
    lastH = h;
  }
  collect();
  return JSON.stringify({n: window.__seen.size, handles: [...window.__seen].sort()});
})()

// Pass 2 (if more scrolling needed) — same code but reads existing window.__seen
// Pass 3 — drain final list:
JSON.stringify([...window.__seen].sort())
```

**Why `[data-testid="UserCell"]` not generic `a[href^="/"]`:** the latter grabs every avatar link in viewport — including suggestions sidebar, which adds non-following accounts. UserCell is the actual following-list cell. A run scraped 137 handles vs a previous local list of 67 — generic-link selector was missing ~70.

## Following-list diff pitfalls (learned 2026-05-21)

When computing `added`/`removed` deltas vs `context/following-list.json`, these are real bugs hit in production. Codified to prevent recurrence.

### Pitfall 1 — Parallel structure (`accounts.*` vs `scan_priority.*`)

`following-list.json` carries TWO parallel structures: `accounts.*` (semantic grouping, 16 sub-buckets) and `scan_priority.*` (priority grouping, 4 buckets). They are NOT auto-synced — a handle can live in one but not the other.

**Symptom:** diff script iterating only `accounts.*` reports false-positive `added` for handles already tracked in `scan_priority.*` (e.g. `@Copilot`, `@OpenAIDevs`, `@VisualStudio` were ONLY in `scan_priority.high_signal_required`, missing from any `accounts.*` bucket).

**Rule:** ALWAYS diff against the UNION of both structures:

```javascript
const union = new Set();
for (const list of Object.values(cur.accounts || {})) for (const h of list) union.add(lc(h));
for (const list of Object.values(cur.scan_priority || {})) for (const h of list) union.add(lc(h));
const added = [...freshSet].filter(h => !union.has(h));
```

**Secondary rule:** when adding a new follow, write to BOTH structures in lockstep — `accounts.<bucket>` + `scan_priority.<tier>`. Single-structure writes accumulate drift over time.

### Pitfall 2 — CDP timeout on long scroll batches

`javascript_tool` calls hit CDP `Runtime.evaluate` timeout (45s default) when a single async JS call scrolls >30 iterations × 700ms sleep. The scroll DID run partially before timeout — `window.__seen` is updated — but the call appears failed and the result isn't returned.

**Rule:** cap scroll batches at ~15 iterations per `javascript_tool` call. For longer lists, either:

1. Multiple sequential `javascript_tool` calls of 10-15 iterations each (cleanest).
2. `setInterval`-based background scroller pattern (fire-and-poll):

   ```javascript
   if (window.__scrollTimer) clearInterval(window.__scrollTimer);
   window.__scrollDone = false; window.__lastH = -1; window.__stable = 0; window.__iter = 0;
   window.__scrollTimer = setInterval(() => {
     /* collect() */
     window.scrollBy(0, window.innerHeight * 0.8);
     window.__iter++;
     /* convergence check on document.body.scrollHeight */
     if (window.__stable >= 8 || window.__iter > 80) { clearInterval(window.__scrollTimer); window.__scrollDone = true; }
   }, 900);
   ```

   Poll `window.__scrollDone` from a separate `javascript_tool` call after 30-60s (use `Bash sleep N run_in_background: true`).

### Pitfall 3 — Brand handle ≠ company handle

The handle `@anthropic` (lowercase, no "AI") is a PERSONAL account (Paul Jankura, Ohioan, "Emphatically not an AI company"). The real Anthropic company account is `@AnthropicAI`. Same trap exists across vendors: `@openai` (personal/squatted?) vs `@OpenAI` (company), etc.

**Rule:** when adding any handle that LOOKS like a brand, verify by visiting the profile and reading the bio. Specifically check: does the bio describe the company, or a person? Is the website link the company's official domain? If unsure, prefer the `AI`-suffixed or known-disambiguated handle (`@AnthropicAI`, `@GoogleAI`, `@OpenAIDevs`).

### Pitfall 4 — Profile drift (engineer moved companies)

Tech personalities change employers frequently. A handle that was "Vercel DevRel" 6 months ago may now be "Claude Code @ Anthropic" — same handle, different signal value. Existing low-signal/uncategorized entries may have become high-signal.

**Rule:** during every `--refresh-following`, also audit existing handles in `uncategorized_creators` + `low_signal_skip_default` for role changes. Specifically check anyone working at: Anthropic, OpenAI, Cursor, Google DeepMind, xAI, Windsurf, Cognition. If they joined a HIGH-priority vendor, recategorize.

**Cadence:** quarterly OR when a refresh detects new follows in the same role-shift cluster (e.g. multiple new Anthropic Claude Code engineers added = re-audit existing engineers for matches).

### Pitfall 5 — Bucket assignment by guess vs verification

When triaging unknown handles, easy to assume bucket from handle name alone. Many "uncategorized_creators" turned out to be high-signal vendor engineers (OmidMogasemi = Claude Code @ Anthropic, `_samirism` = OpenAI ChatGPT Memory, derrickcchoi = OpenAI Codex, poteto = Cursor + React compiler, taehkimmm = Cursor).

**Rule:** for any handle without a clear bucket, visit the profile and read the bio before assigning. Single nav + JS extraction ≈ 3s per profile — cheap insurance vs lost signal.

## Per-Profile Extraction Steps

### 1. Check chrome availability

```
mcp__claude-in-chrome__tabs_context_mcp (with createIfEmpty: true)
```

### 2. Load account list + filter by priority

Read `context/following-list.json`. **Default scan strategy:**

- **All `high_signal_required` profiles** — always scan, full date range
- **All `medium_signal`** — scan, full date range
- **`low_signal_skip_default`** — scan by default (scope=all). Drop only when `--skip-low-signal` flag set OR adaptive scope demotion (SKILL.md standing default #19) fires after consecutive quiet runs.
- **`leadership_low_volume`** — scan but cap at 1 scroll iteration (these accounts post <5x/week)

For an 11-day window with the active list: expect ~160 profiles in active scan at scope=all, ~80 at scope=all-non-skip.

### 3. Per-profile loop: navigate → wait 3s → extract

Use `browser_batch` to combine navigate + wait + extract in one call. Each profile takes ~5-8 seconds.

### 4. Handle results

- **0 tweets in window** → mark as low-signal candidate for next session, move on
- **1+ tweets** → record all, move to next
- **`[BLOCKED: Cookie/query string data]`** → fall through to **screenshot fallback**
- **No `tweetText` elements at all** → profile may be private/empty; verify with screenshot

### 5. Fallback ladder for cookie-blocked / DOM-rewrite scenarios

Some profiles trigger the cookie filter on `javascript_tool`. **4-tier fallback** (try in order):

```
Tier 1: javascript_tool extractor (default) — fails with [BLOCKED: Cookie/query string data]
Tier 2: computer scroll + get_page_text — returns plain text of articles
        Capture handle/date/topic, build URLs by hand
Tier 3: read_page (claude-in-chrome accessibility tree) — structured DOM representation
        Useful when get_page_text returns flattened text without article boundaries
Tier 4: computer screenshot — manual extraction (last resort)
```

Verified profiles for screenshot fallback: `@ClaudeCodeLog`, `@minchoi`, `@mavi888uy`, `@embirico`. Pattern: high-follower verified accounts more likely to trigger filter.

### 6. Per-stage state writes

The per-profile runner writes `context/runs/<run-id>/per-profile/<NNN>-<handle>.json` after **every** stage (S1 → S6) and `master.json` after S6. Survives mid-run compaction or interruption — re-run resumes from `master.json.current_index`.

See `per-profile-loop.md` "S1 Capture" for the per-profile JSON schema written after S1.

## X profile-page 7-day infinite-scroll limit

**Empirically verified:** even with `scrollTo(0, document.body.scrollHeight)` repeated 8x with 2.2s waits, profile pages stop loading content beyond ~7 days for high-volume accounts. This is X's pagination limit on the `/{user}` Posts tab, NOT a scroll-tuning issue.

**For windows >7 days, fallbacks (in priority order):**

1. **Twitter Advanced Search (PRIMARY for >7d)** — date-bounded query, no scroll limit. URL pattern:

   ```
   https://twitter.com/search?q=from%3A{handle}%20since%3A{YYYY-MM-DD}%20until%3A{YYYY-MM-DD}&f=live
   ```

   - URL-encode `:` as `%3A`, spaces as `%20`
   - `f=live` for chronological order (vs `f=top` algorithmic)
   - **Use `since` and `until` together** to bound both edges — without `until`, results are unbounded forward and may include too many recent tweets that Wave 1 already covered
   - **Run the force-scroll extractor on search results** — same `[data-testid="tweetText"]` + `article time` selectors apply. Date filter enforced by URL, dedup against Wave 1 captures via URL set.
   - **Caveat:** Advanced Search excludes some sponsored/promoted tweets and certain reply-only content. Use as **complement to**, not replacement for, profile-page scan.

2. **`x.com/{handle}/with_replies`** tab — extends history because reply-quoted threads bring older content. Same selectors. Use when Advanced Search misses thread-quoted content.

3. **`/media`** tab — for accounts where image/video content is the signal

4. **Direct status URL navigation** — if you have one tweet URL, the parent account's other tweets at nearby times are sometimes accessible via X's "Show more" navigation

**Wave 1.5 in `/ai-briefing:ai-briefing` skill** (see SKILL.md): when `--since >7d`, automatically runs Advanced Search pass on the high-volume account list (sama, gdb, AnthropicAI, claudeai, OfficialLoganK, etc.) after Wave 1 profile-page scan. Combined coverage hits ~99% of date window for those accounts.

### Advanced Search extractor

Same JS works unchanged — search results render `article` elements with `tweetText` and `time` just like profile pages:

```javascript
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const seen = new Set();
  const results = [];
  let stable = 0;
  for (let i = 0; i < 20; i++) {
    const tweets = document.querySelectorAll('[data-testid="tweetText"]');
    let newC = 0;
    tweets.forEach(tw => {
      const art = tw.closest('article');
      if (!art) return;
      const sl = art.querySelectorAll('a[href*="/status/"]');
      const url = sl.length > 0 ? 'https://x.com' + sl[0].getAttribute('href') : '';
      const t = art.querySelector('time');
      if (!t) return;
      if (seen.has(url)) return;
      seen.add(url);
      const author = art.querySelector('a[href^="/"][role="link"] > div > span');
      const txt = tw.textContent.replace(/\n/g, ' ').trim().substring(0, 200);
      results.push({t: txt, u: url, d: t.getAttribute('datetime').substring(0, 16)});
      newC++;
    });
    if (newC === 0) stable++; else stable = 0;
    if (stable >= 3) break;
    window.scrollBy(0, window.innerHeight * 2);
    await sleep(1300);
  }
  return JSON.stringify({n: results.length, tw: results});
})()
```

### Building the search URL

```python
import urllib.parse
def adv_search_url(handle, since_iso, until_iso):
    h = handle.lstrip('@')
    q = f"from:{h} since:{since_iso[:10]} until:{until_iso[:10]}"
    return f"https://twitter.com/search?q={urllib.parse.quote(q)}&f=live"
```

Example output: `https://twitter.com/search?q=from%3Asama%20since%3A2026-04-24%20until%3A2026-05-05&f=live`

### High-volume account list (Wave 1.5 default)

Apply Advanced Search to these when window >7d:

```
@sama, @gdb, @thsottiaux, @OpenAIDevs, @AnthropicAI, @claudeai, @ClaudeCodeLog,
@OfficialLoganK, @Google, @GoogleAIStudio, @karpathy, @simonw, @swyx, @LangChain,
@bunjavascript, @code, @TechCrunch, @GithubProjects, @firecrawl, @cursor_ai
```

These post 5+ tweets/day; profile-page scroll limit bites hardest. Other accounts in `following-list.json` rarely need Advanced Search.

## Performance learnings

### Timing (per profile)

- **~5-8s per profile**: nav (1s) + wait (3s) + extract+scroll (1-4s)
- **60 profiles ≈ 8-10 min** per pass
- **Most profiles have 0-3 tweets** in 11-day window; ~40% have any content
- **High-value profiles** (sama, gdb, AnthropicAI, claudeai, OfficialLoganK, OpenAIDevs) average 7-25 tweets per 11-day window

### Browser stability

- Chrome MCP extension occasionally disconnects mid-batch (~1-2 times per 60-profile session). Recovery: re-call `tabs_context_mcp` to confirm tab ID still valid, retry batch.
- 3-profile `browser_batch` sometimes triggers "did not respond in time" on profiles with heavy JS (auto-playing videos). Cap at **2 profiles per browser_batch** for stability.
- Scrolling JavaScript should `await sleep(1200-1500ms)` between scroll calls — shorter waits cause X's lazy-load to not render before the next collect call.

### Accuracy gotchas

- **Retweets show original author URL** — handle extracted from profile is retweeter, but URL points to original poster. Both preserved.
- **Pinned tweets** sometimes have timestamps outside window (returns from years ago). `cutoff` filter handles this.
- **Threads**: only first tweet of a thread appears in profile view. Don't bother navigating into individual threads for briefing scope.
- **Ads filtered automatically** — they lack `time` elements.

### Cookie/query-string filter (chrome MCP server-side)

The MCP server has a content filter that returns `[BLOCKED: Cookie/query string data]` when the JS execution result triggers heuristics for sensitive data. Triggered on **~5% of profiles**. Pattern uncertain — high-follower verified accounts seemingly more likely. Use screenshot fallback (Step 5).

## Surface 2 — `/{handle}/with_replies` pass

**Mandatory** for every handle in `high_signal_required` after the Posts pass completes. Opt-in for `medium_signal` via `--with-replies-medium` flag.

The same force-scroll JS works unchanged (selectors `[data-testid="tweetText"]`, `article[data-testid="tweet"]`, `time` are identical). What changes is the URL and a post-extract filter to drop replies-to-others (high-noise).

### URL pattern

```
https://x.com/{handle}/with_replies
```

### Replies extractor — with_replies + reply-to-others filter

Scroll cap raised to 16 (vs 12 for Posts): denser tweet sequences in `/with_replies` (every self-reply rendered, vs Posts collapsing threads to first tweet only) exhaust scroll budget faster.

```javascript
(async () => {
  const cutoff = new Date('{cutoff_iso}');
  const handle = '{handle}';  // bare handle, no @
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const seen = new Set();
  const results = [];
  let stable = 0;

  for (let i = 0; i < 16; i++) {
    const tweets = document.querySelectorAll('[data-testid="tweetText"]');
    let newC = 0;
    tweets.forEach(tw => {
      const art = tw.closest('article');
      if (!art) return;
      // Filter: keep only tweets the handle authored (drops replies-to-others)
      const authored = art.querySelector(`a[href^="/${handle}/status/"]`);
      if (!authored) return;
      const url = 'https://x.com' + authored.getAttribute('href');
      const t = art.querySelector('time');
      if (!t) return;
      const ts = new Date(t.getAttribute('datetime'));
      if (ts < cutoff) return;
      if (seen.has(url)) return;
      seen.add(url);
      const txt = tw.textContent.replace(/\n/g, ' ').trim().substring(0, 200);
      results.push({t: txt, u: url, d: t.getAttribute('datetime').substring(0, 16)});
      newC++;
    });

    let past = false;
    document.querySelectorAll('article time').forEach(t => {
      if (new Date(t.getAttribute('datetime')) < cutoff) past = true;
    });
    if (past && i >= 2) break;
    if (newC === 0) stable++; else stable = 0;
    if (stable >= 3) break;

    window.scrollBy(0, window.innerHeight * 2);
    await sleep(1300);
  }
  return JSON.stringify({a: '@' + handle, surface: 'with_replies', n: results.length, tw: results});
})()
```

### Dedup against Posts pass

with_replies often surfaces tweets already captured on the Posts tab (the parent thread tweet). Dedup via canonical URL set; `seen-items.json` already does this at the items level — the `url` field is the dedup key.

### What with_replies adds

- Self-reply threads (the *primary* feature-drop signal — handle posts thread, replies with screenshots/links/details)
- Quote-tweets (already shown on Posts tab — duplicate, deduped)
- Replies-to-others by the handle (filtered OUT by the `a[href^="/{handle}/status/"]` filter — drops noise)

## Surfaces 3+4 — Home feed extraction (Following + For you)

Two platform changes require new mechanics:

1. **Following sort default → Grok-ranked** (2025-11-27 onwards). Must DOM-click `⋯` → `Most Recent` to force chronological.
2. **Tab persistence bug** (Dec 2025+). Desktop X reverts to `For you` on every navigation. No URL parameter forces the tab. Must DOM-click `Following` tab post-navigation.

### Step 1: Force Following tab + Most Recent

```javascript
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  // Wait for tab strip to load (react hydration is async)
  let followingTab = null;
  for (let i = 0; i < 50; i++) {
    const tabs = document.querySelectorAll('[role="tab"]');
    followingTab = [...tabs].find(t => /^Following$/i.test(t.textContent.trim()));
    if (followingTab) break;
    await sleep(100);
  }
  if (!followingTab) return JSON.stringify({step: 'following', ok: false, reason: 'tab-not-found'});
  followingTab.click();
  await sleep(800);

  // Click ⋯ / kebab on Following timeline header to expose sort menu
  const headerKebab = document.querySelector('header [role="button"][aria-haspopup]') ||
                      [...document.querySelectorAll('[role="button"]')].find(b => {
                        const al = (b.getAttribute('aria-label') || '').toLowerCase();
                        return /sparkle|sort|more|⋯/.test(al) && b.closest('header,[role="banner"]');
                      });
  if (!headerKebab) return JSON.stringify({step: 'kebab', ok: false, reason: 'kebab-not-found'});
  headerKebab.click();
  await sleep(500);

  // Click "Most Recent" / "Latest" menu item
  const items = [...document.querySelectorAll('[role="menuitem"], [role="option"]')];
  const target = items.find(i => /(most recent|latest|see most recent)/i.test(i.textContent));
  if (!target) return JSON.stringify({step: 'most-recent', ok: false, reason: 'item-not-found'});
  target.click();
  await sleep(800);

  return JSON.stringify({step: 'all', ok: true});
})()
```

**If any step returns `ok: false`**, fall through — Home Following extraction is opportunistic, not load-bearing. Profile passes (Surfaces 1+2) cover the same handles.

### Step 2: Force-scroll on Home Following

Same Posts-surface extractor, capped at 8 scrolls (lower than profile's 12 — feed cycles into ads/suggestions sooner).

```javascript
// (same JS as profile pass, but with `for (let i = 0; i < 8; i++)`)
```

### Step 3: For you tab pass

```javascript
// Navigate fresh to /home (For you is default after the Following session)
// OR programmatically click For-you tab:
const forYou = [...document.querySelectorAll('[role="tab"]')].find(t => /^For you$/i.test(t.textContent.trim()));
if (forYou) forYou.click();
// Wait + run extractor with 6-scroll cap
```

For-you surfaces algo-promoted accounts not in following-list. Always supplementary; dedup against profile passes via canonical URL.

### Skipping ads + "Who to follow"

Sponsored cards lack `time` elements. The extractor's `if (!t) return;` filters them automatically. No additional logic needed.

## Chunked retrieval

**Truncation finding (empirical).** `mcp__claude-in-chrome__javascript_tool` truncates responses at ~1500-2000 chars regardless of how much data the JS captured. Direct repro on `@AnthropicAI` with the 80-char text cap: 13 tweets returned a JSON string that ended mid-tweet at the truncation boundary; tail-end data was silently lost. Truncation occurs in the MCP transport layer, not in the JS execution. Affects any data-extraction MCP pattern returning JSON > ~1.5 KB.

**Mitigation: chunked retrieval via window stash.** The exported extractor templates stash the full result on `window.__capPosts` (Posts surface) / `window.__capReplies` (replies surface) and return only a small summary `{n, oldest?, stable_iterations}`. The main session then issues 1+ `javascript_tool` calls that read `window.__cap{Posts,Replies}.tw.slice(start, end)` in `CHUNK_SIZE`-tweet slices and reassembles the original extractor shape locally. Chrome MCP calls do NOT count toward Claude burst budget — they are in-session tool calls — so the extra round-trips are free against rate limits.

**`CHUNK_SIZE` default:** `2`. Per-tweet bytes ≈ 700-1000 with the current TweetSchema (text + url + datetime + external_links + card + quoted_tweet + metrics). 2 × ~700 = ~1400 fits the ~1500-2000 char MCP javascript_tool cap with ~30% headroom. Raising requires byte-budget recalc.

**Helpers exported from `lib/chrome-extract.js`:**

| Export | Purpose |
|---|---|
| `CHUNK_SIZE` | tuning constant — see byte budget above |
| `buildChunkReaderJs(surface, start, end)` | returns `JSON.stringify(window.__cap${Posts\|Replies}.tw.slice(start, end))` for `mcp__claude-in-chrome__javascript_tool` |
| `assembleChunks(summary, chunks, {handle, surface})` | reconstructs full extractor output from summary + chunk arrays; returns shape-validated object via `validateExtractorOutput` |

**Main-session chunk sub-loop (per surface):**

```text
1. javascript_tool(buildExtractorJs(...).js)         → returns `{n, oldest?, stable_iterations}`, stashes to window.__capPosts
2. for s in 0..summary.n step CHUNK_SIZE:
     javascript_tool(buildChunkReaderJs('posts', s, s + CHUNK_SIZE))   → returns JSON-stringified tweet array
3. tw = assembleChunks(summary, chunks, {handle, surface: 'posts'})    → full {a, n, oldest, stable_iterations, tw[]}, zod-validated
4. write {posts: tw, replies: <same pattern>|null} to tmp file
5. node per-profile-runner.js commit-s1 --index=N --captures=<tmpfile>
```

If `summary.n === 0`, skip the chunk sub-loop and call `assembleChunks(summary, [], {handle, surface})` directly — produces an empty `tw[]` which `commit-s1` accepts (S2 just records 0 captures, marks profile partial).

**Recheck:** if Anthropic raises the MCP `javascript_tool` response cap (or removes it for stash-mode reads), chunked retrieval can be removed in favor of single-call extraction. Re-validate via direct test against a known high-volume profile.

## Tweet schema

The extractor templates capture four optional fields per tweet on top of the base `{t, u, d}` shape (text / status URL / datetime). All fields are zod `.optional()`.

### Selectors

| Field | Selector | Notes |
|---|---|---|
| `external_links[]` | `[data-testid="tweetText"] a[href*="t.co"]` → `getAttribute('href')` for resolved URL + `textContent` for display | Cap **2 per tweet** (byte budget). Skip self-references (twitter.com / x.com domains). Each entry: `{href, text}` |
| `card` | `article [data-testid="card.wrapper"]` → first child `a[href]` for URL + `[data-testid="card.layoutLarge.detail"]` text for title (≤100 chars) + `img[src]` for image + parsed hostname for domain | Permissive — fields stripped when null; whole `card` set to null when no fields populated |
| `quoted_tweet` | nested `article [data-testid="tweet"] [data-testid="tweet"]` → inner `[data-testid="tweetText"]` text + inner `a[href*="/status/"]` URL + handle parsed from URL path | Single-level recursion only (`inner !== art` guard). No quote-of-quote. |
| `metrics` | `[data-testid="like"]` / `[data-testid="retweet"]` / `[data-testid="reply"]` → child `[data-testid="app-text-transition-container"] span` textContent OR aria-label fallback. Counts parsed via `parseAbbreviated()` ("1.2K" → 1200) | NULL on missing testid. `{likes, reposts, replies}` shape; whole `metrics` omitted when all 3 null |

### CRITICAL — `data-testid="retweet"` NOT `"repost"`

X officially rebranded "Retweet" → "Repost" in the UI in 2023, but the internal `data-testid` attribute on the engagement button **remains `"retweet"`**. The aria-label updates to "Repost" (e.g. `aria-label="1,234 reposts"`) but the testid does not. This is a backward-compat pattern X's own internal Playwright/Puppeteer tests rely on.

Multi-source consensus (XActions, twint, drawrowfly, viperlike + manual DOM inspection). Do NOT change to `"repost"` without empirical re-verification (paste extractor JS into chrome console on a real X tweet, check the resulting metrics object).

### `parseAbbreviated()` helper

Exported from `lib/chrome-extract.js`. Parses X engagement count strings to integers:

```js
parseAbbreviated('1.2K')          // → 1200
parseAbbreviated('12.4K')         // → 12400
parseAbbreviated('1.2M')          // → 1200000
parseAbbreviated('1,234')         // → 1234
parseAbbreviated('1,234 likes')   // → 1234   (aria-label fallback form)
parseAbbreviated('0')             // → 0
parseAbbreviated('')              // → null
parseAbbreviated(null)            // → null
parseAbbreviated('abc')           // → null
```

Inlined inside extractor JS templates (browser execution context — no module imports). Also re-exported for Node-side tests in `chrome-extraction.test.js`.

### S3 prompt budget — `slimForPrompt`

The full tweet shape is too verbose to dump 50× into the S3 synthesize prompt (~+30k tokens at 50-tweet cap). `lib/synthesize-agent.js` exports `slimForPrompt(tweet)`:

- Keeps `t/u/d` always
- Top 1 `external_links` href only (drops display text — S3 only needs the URL for primary-pairing)
- `card` → `{url, title (≤60 chars)}` only
- `metrics` → packed `"L/R/Re"` string (e.g. `"1234/56/12"` or `"1234/-/12"` for nulls)
- **Intentionally OMITS `quoted_tweet`** body — quoter's tweet text is already in `t`

Net cost: ~+50 bytes/tweet vs raw bloat (~+700). 50-tweet prompt grows by ~2.5KB instead of ~35KB.

### Out of scope

The current schema fills the byte budget. Additions like `attachments[]` (image/video metadata), `hashtags[]`, or `mentions[]` would require either further `CHUNK_SIZE` reduction (doubling roundtrips), two-pass extraction (text-only first, media in follow-up call), or Anthropic raising the MCP javascript_tool response cap.

Tested in `scripts/chrome-extraction.test.js` (no live Twitter access required).

## Limitations

- **Not backgroundable**: needs Chrome open, user idle
- **Fragile to UI changes**: `data-testid="tweetText"` and `data-testid="UserCell"` are stable selectors but X has changed these before. Fallback: `get_page_text` returns plain text from articles
- **Anti-bot detection**: lower risk with real browser+real auth; rapid navigation could trigger challenges. 3-second wait between profiles helps. Cap at ~100 profile navigations per session.
- **Media-only tweets** (only images/videos, no text): won't have `tweetText` elements. Acceptable miss — text announcements are primary value.
- **Following list virtualization**: must use `window.__seen` persistence pattern (see above)
- **7-day scroll limit on `/{user}` Posts**: use `with_replies` tab or Advanced Search for older content

## Workflow defaults (session-level)

These are the standing assumptions — don't ask user, just do. Override only if user passes contrary flag.

| Default | Behavior |
|---|---|
| **Add-only mode** | Append new items to `output/meetings/latest.md` + `rolling.md`. Never overwrite. Updates `seen-items.json` incrementally. |
| **Thorough date-scan** | Use force-scroll extractor. Don't accept first-viewport-only on accounts likely to have multiple tweets. |
| **Retry blocked** | First-pass failures (`[BLOCKED]` or empty result on a profile that should have content) get screenshot fallback in same session. |
| **Per-stage state writes** | Runner persists per-profile JSON after every stage; survives auto-compact. |
| **Scope=all default** | Scan every bucket including `low_signal_skip_default` by default. Drop LOW via `--skip-low-signal` or adaptive demotion. |
| **Cap leadership accounts at 1 scroll** | DarioAmodei, JeffDean, etc. post <5x/week — full deep-scroll wastes time. |
| **2-profile cap per `browser_batch`** | Stability — 3+ occasionally times out. |
| **with_replies MANDATORY for `high_signal_required`** | Every high-signal handle gets both Posts + with_replies passes. Catches feature-drop scoops collapsed in Posts tab (e.g. Blender plugin announcement). |
| **with_replies opt-in for `medium_signal`** | Off by default; pass `--with-replies-medium` to enable. |
| **Force Following tab + Most Recent on Home** | Default Following sort is Grok-ranked since 2025-11-27. DOM-click `Following` then `⋯` → `Most Recent` to get chronological. |
| **DOM-click Following on every Home navigation** | Tab-persistence bug since Dec 2025 reverts to For-you. Click Following each time. |
| **Session preflight: selector probe** | First profile after session start runs the selector-presence probe before bulk extraction. If `ok:false`, abort + escalate. |
| **Per-session cap: 100 profile navs + 30 advanced searches** | Stays under undocumented anti-bot threshold (Sorsa 500 reads/day soft ceiling). |
| **Live following diff every 4-6 weeks** | Re-scrape `x.com/{user}/following` and update `following-list.json`. New follows tend to be the highest-signal accounts (user actively curated). |
