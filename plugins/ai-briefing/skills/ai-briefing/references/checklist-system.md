# Run Checklist Verification System

> **DEPRECATION NOTE (2026-05-06):** The Wave 1 portion of this checklist (`wave_1_profiles[]` rows) is **superseded** by the per-profile runner state machine. See `per-profile-loop.md` + `runner-architecture.md`. Wave 1 progress now lives in `context/runs/<run-id>/master.json` + `per-profile/<NNN>-<handle>.json`. The Wave 1.5 / Wave 2 / Wave 3 / Wave 4 checklist sections below are still authoritative — use this checklist for non-profile coverage only. Verification gate (Step 6.5) still applies; consult `master.json` for Wave 1 status alongside the Wave 1.5/2/3/4 rows here.

Deterministic verification that **every profile** in scan_priority got coverage **across the full date window**, and **every Wave 3 source** was checked. Required for high-confidence completeness.

## Why this exists

Without enforced checklist, completion gets eyeballed:

- "I scanned the high-value profiles" — but did all 30 finish? Was one skipped due to MCP disconnect?
- "Coverage looks good" — but did posts force-scroll actually reach cutoff for sama? Or did it stop at 7-day limit?
- "Done" — but did Wave 3 actually pull RSS for all 4 providers, or just the first that didn't 404?

Checklist makes coverage **provable** instead of asserted. Each row gets `complete` / `partial` / `skipped` / `failed`. Any non-`complete` row blocks the "done" declaration unless user explicit-skips with reason.

## State file: `context/run-checklist-{ISO_DATE}.json`

Created at run start, updated incrementally during run, frozen at end. Format:

```json
{
  "run_id": "2026-05-19T09:00:00Z",
  "cutoff": "2026-05-05T00:00:00Z",
  "until": "2026-05-19T09:00:00Z",
  "window_days": 14,
  "providers_in_scope": ["anthropic", "openai", "google", "cursor", "other", "extras"],
  "started_at": "2026-05-19T09:00:00Z",
  "completed_at": null,
  "wave_1_profiles": [
    {
      "handle": "@bcherny",
      "category": "anthropic_claude_code",
      "priority": "high_signal_required",
      "status": "complete",
      "scanned_at": "2026-05-19T09:02:14Z",
      "tweets_in_window": 1,
      "oldest_captured": "2026-05-15T08:00:00Z",
      "cutoff_reached": true,
      "scroll_iterations": 3,
      "fallback_used": null,
      "notes": null
    },
    {
      "handle": "@sama",
      "category": "openai_team",
      "priority": "high_signal_required",
      "status": "partial",
      "scanned_at": "2026-05-19T09:04:01Z",
      "tweets_in_window": 22,
      "oldest_captured": "2026-05-12T15:00:00Z",
      "cutoff_reached": false,
      "scroll_iterations": 14,
      "fallback_used": "advanced_search_pending",
      "notes": "Hit X 7-day scroll limit. Wave 1.5 will close gap."
    },
    {
      "handle": "@ClaudeCodeLog",
      "category": "anthropic_brand",
      "priority": "high_signal_required",
      "status": "complete",
      "scanned_at": "2026-05-19T09:05:22Z",
      "tweets_in_window": 4,
      "oldest_captured": "2026-05-06T00:00:00Z",
      "cutoff_reached": true,
      "scroll_iterations": 5,
      "fallback_used": "screenshot",
      "notes": "javascript_tool BLOCKED by cookie filter — used screenshot+get_page_text successfully."
    }
  ],
  "wave_1_5_advanced_search": [
    {
      "handle": "@sama",
      "url": "https://twitter.com/search?q=from%3Asama%20since%3A2026-05-05%20until%3A2026-05-19&f=live",
      "status": "complete",
      "tweets_added": 8,
      "scanned_at": "2026-05-19T09:18:30Z",
      "notes": "Closed Wave 1 gap — 8 additional tweets between cutoff and Wave 1 oldest."
    }
  ],
  "wave_2_perplexity_websearch": [
    {"provider": "anthropic", "tool": "perplexity_ask", "status": "complete", "result_count": 6},
    {"provider": "anthropic", "tool": "WebSearch", "status": "complete", "result_count": 8},
    {"provider": "openai", "tool": "perplexity_ask", "status": "complete", "result_count": 9}
  ],
  "wave_3_rss_changelogs_releases": [
    {"source": "anthropic.com/news/rss.xml", "type": "rss", "status": "complete", "items_in_window": 4},
    {"source": "code.claude.com/docs/en/changelog", "type": "html", "status": "complete", "items_in_window": 7},
    {"source": "anthropics/claude-code", "type": "github_releases", "status": "complete", "items_in_window": 12},
    {"source": "openai.com/blog/rss.xml", "type": "rss", "status": "failed", "error": "404 Not Found", "fallback": "WebFetch on openai.com/blog completed"}
  ],
  "wave_4_extras": [
    {"query": "robotics breakthroughs", "tool": "perplexity_ask", "status": "complete", "result_count": 5}
  ],
  "verification_summary": {
    "total_rows": 0,
    "complete": 0,
    "partial": 0,
    "skipped": 0,
    "failed": 0,
    "completion_pct": 0.0,
    "blocking_issues": []
  }
}
```

## Status values

| Status | Meaning |
|---|---|
| `complete` | Row fully covered. For profiles: cutoff_reached=true OR oldest_captured within 24h of cutoff. For Wave 3: source returned data + fully parsed. |
| `partial` | Row partially covered. Profile cutoff not reached AND fallback not yet used. Wave 3 source returned data but parse incomplete. **Blocks done declaration unless user explicit-accepts.** |
| `skipped` | Row intentionally skipped — `--skip-low-signal` set OR adaptive scope (standing default #19) demoted to `all-non-skip`/`high`. Logged but not blocking. |
| `failed` | Row attempted but errored (MCP disconnect, 404, timeout). **Blocks done declaration unless user explicit-skips with reason.** |
| `pending` | Not yet attempted. End-of-run state should never have these. |

## Workflow integration

### Step 0.5 — Build checklist (after Step 0 args parsing)

```python
import json
from pathlib import Path
from datetime import datetime, timezone

following = json.loads(Path('context/following-list.json').read_text(encoding='utf-8'))
priorities = following['scan_priority']

# Build row per profile based on flag combination
rows = []
buckets_to_scan = ['high_signal_required', 'medium_signal', 'leadership_low_volume']
if args.get('all'):
    buckets_to_scan.append('low_signal_skip_default')

for bucket in buckets_to_scan:
    for handle in priorities[bucket]:
        rows.append({
            'handle': handle,
            'category': lookup_category(handle, following['accounts']),
            'priority': bucket,
            'status': 'pending',
            'scanned_at': None,
            'tweets_in_window': 0,
            'oldest_captured': None,
            'cutoff_reached': False,
            'scroll_iterations': 0,
            'fallback_used': None,
            'notes': None
        })

# Mark low_signal_skip_default as 'skipped' upfront (don't even attempt)
scope = args.get('scope') or adaptive_pick(state['current_meeting_window'])  # standing default #19
include_low = scope == 'all' and not args.get('skip_low_signal')
if not include_low:
    for handle in priorities['low_signal_skip_default']:
        rows.append({
            'handle': handle,
            'priority': 'low_signal_skip_default',
            'status': 'skipped',
            'notes': f'dropped by scope={scope} (--skip-low-signal or adaptive demotion)'
        })

checklist = {
    'run_id': datetime.now(timezone.utc).isoformat(),
    'cutoff': cutoff_iso,
    'until': now_iso,
    'window_days': window_days,
    'wave_1_profiles': rows,
    'wave_1_5_advanced_search': build_advanced_search_rows(window_days),
    'wave_2_perplexity_websearch': build_wave2_rows(providers),
    'wave_3_rss_changelogs_releases': build_wave3_rows(),
    'wave_4_extras': [{'query': '...', 'tool': 'perplexity_ask', 'status': 'pending'}] if extras else []
}
Path(f'context/run-checklist-{run_date}.json').write_text(json.dumps(checklist, indent=2))
```

### Per-profile completion criteria

A Wave 1 profile row is `complete` when ALL of:

1. `scanned_at` is set (navigation succeeded)
2. posts extractor returned without error (or fallback succeeded)
3. Either:
   - `cutoff_reached: true` (extractor saw a tweet older than cutoff during scroll), OR
   - `oldest_captured` is within 24 hours of `cutoff` (account just doesn't post that often), OR
   - `tweets_in_window: 0` AND scroll hit `stable >= 3` (account silent during window — verified by reaching end of feed)

If `cutoff_reached: false` AND `oldest_captured` is more than 24h after `cutoff` AND profile is in Wave 1.5 high-volume list → status starts as `partial`. Wave 1.5 Advanced Search must then run; on success, promote to `complete`. On Wave 1.5 failure → stays `partial`.

### Per-Wave 3 source completion

| Source type | Complete when |
|---|---|
| RSS feed | HTTP 200 + valid XML parsed + items filtered by pubDate |
| HTML changelog | HTTP 200 + page contains expected version markers |
| GitHub releases | `gh api` returned 200 + jq filter applied |

On RSS 404 → fallback to HTML scrape of parent blog URL → if that succeeds, `status: complete` with `fallback: WebFetch`. If both fail → `status: failed`.

### Mid-run checkpoints

After each Wave completes, write checklist back to disk. Survives auto-compact. Same pattern as `chrome-scan-results.json` (every 5 profiles).

```python
def update_row(checklist_path, wave_key, handle, **updates):
    cl = json.loads(checklist_path.read_text(encoding='utf-8'))
    for row in cl[wave_key]:
        if row.get('handle') == handle or row.get('source') == handle:
            row.update(updates)
            row['scanned_at'] = datetime.now(timezone.utc).isoformat()
            break
    checklist_path.write_text(json.dumps(cl, indent=2))
```

### End-of-run verification gate (Step 7)

**Before declaring done, run verification:**

```python
def verify_checklist(cl):
    all_rows = (cl['wave_1_profiles']
                + cl.get('wave_1_5_advanced_search', [])
                + cl['wave_2_perplexity_websearch']
                + cl['wave_3_rss_changelogs_releases']
                + cl.get('wave_4_extras', []))
    summary = {
        'total_rows': len(all_rows),
        'complete': sum(1 for r in all_rows if r['status'] == 'complete'),
        'partial': sum(1 for r in all_rows if r['status'] == 'partial'),
        'skipped': sum(1 for r in all_rows if r['status'] == 'skipped'),
        'failed': sum(1 for r in all_rows if r['status'] == 'failed'),
        'pending': sum(1 for r in all_rows if r['status'] == 'pending'),
    }
    blocking = [r for r in all_rows if r['status'] in ('partial', 'failed', 'pending')]
    summary['completion_pct'] = round(100 * summary['complete'] / max(summary['total_rows'] - summary['skipped'], 1), 1)
    summary['blocking_issues'] = [
        {'handle_or_source': r.get('handle') or r.get('source') or r.get('query'),
         'status': r['status'],
         'reason': r.get('notes') or r.get('error') or 'no notes'}
        for r in blocking
    ]
    return summary

summary = verify_checklist(cl)
cl['verification_summary'] = summary
cl['completed_at'] = datetime.now(timezone.utc).isoformat()
```

### Done-gate logic

- If `summary['blocking_issues']` is empty → emit briefing + declare done
- If non-empty → present blocking list to user with options:
  1. **Retry blocking items** — re-run failed/partial rows with extended timeout / different fallback
  2. **Accept partial coverage** — user explicit-skips with reason, status promoted to `skipped`, run completes
  3. **Cancel run** — preserve checklist for next session, declare incomplete

Default action when running autonomously (no user available): retry once, then accept partial with `notes: "auto-accepted partial after retry"`.

## Output format addition

Briefing markdown footer includes verification block:

```markdown
---

## Coverage Verification

- **Total rows checked:** 87 (61 profiles + 20 Adv Search + 6 Wave 3 sources)
- **Complete:** 84 (96.6%)
- **Partial:** 1 (@sama hit X 7d limit; Wave 1.5 closed but oldest still ~26h gap)
- **Skipped:** 0 (scope=all default) OR N (when --skip-low-signal set or adaptive scope demoted)
- **Failed:** 0

✓ All `high_signal_required` profiles scanned to cutoff.
✓ All RSS feeds + 5 changelogs + 18 GH repos checked.

Run-checklist: `context/run-checklist-2026-05-19.json`
```

User reads this and **knows** at a glance whether briefing is trust-worthy or has gaps to chase down.

## Display during run

Print compact progress every N profiles:

```
[Wave 1] 23/61 complete · 1 partial · 0 failed · ETA ~3min
[Wave 1] 47/61 complete · 2 partial · 0 failed · ETA ~1.5min
[Wave 1] 61/61 complete — moving to Wave 1.5
```

After Wave 1.5: report which profiles were promoted from `partial` → `complete`.

## CLI inspection

User can inspect anytime:

```bash
# Quick coverage glance
jq '.verification_summary' ${CLAUDE_PLUGIN_DATA}/<profile>/context/runs/<run-id>-checklist.json

# Find what's blocking
jq '.verification_summary.blocking_issues' ${CLAUDE_PLUGIN_DATA}/<profile>/context/runs/<run-id>-checklist.json

# All partial profiles
jq '.wave_1_profiles[] | select(.status == "partial")' ${CLAUDE_PLUGIN_DATA}/<profile>/context/runs/<run-id>-checklist.json

# Diff coverage between two runs
diff <(jq -S '.wave_1_profiles' run-checklist-2026-05-05.json) \
     <(jq -S '.wave_1_profiles' run-checklist-2026-05-19.json)
```

## Retention

Keep last 6 checklists (3 months at 2-week cadence). Older ones move to `output/meetings/archive/checklists/`. Retention pruning runs automatically on `--meeting-prep` runs.
