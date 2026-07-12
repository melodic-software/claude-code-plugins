# Meeting window state

Full schema + lifecycle for `current_meeting_window` in `seen-items.json`. The cutoff is anchored on the **current meeting window**, NOT the last run. Multiple runs between meetings all share the same cutoff and accumulate findings into one output file.

## Table of contents

- Cutoff determination logic
- current_meeting_window schema
- Window lifecycle
- Window-status / close-meeting short-circuit

## Cutoff determination logic

```python
state = read_seen_items()
window = state.get('current_meeting_window')

if args.get('since'):
    cutoff = parse_since(args['since'])  # explicit override
elif window and window['status'] == 'open':
    cutoff = window['opened_date']  # roll-forward: same cutoff across all runs in this window
elif state.get('last_meeting_date'):
    cutoff = state['last_meeting_date']  # window not yet opened; will open in Step 0.6
else:
    cutoff = now - 14  # cold start
```

**First-time / window-closed** → Step 0.6 opens a new window (see lifecycle below).

**Cap:** if computed cutoff is >30 days back, warn user — long windows = many requests + likely incomplete coverage due to X 7d scroll limit even with Wave 1.5.

## current_meeting_window schema

```json
{
  "current_meeting_window": {
    "meeting_n": 27,
    "status": "open",
    "opened_date": "2026-05-19T00:00:00Z",
    "target_close_date": "2026-06-02T00:00:00Z",
    "actual_close_date": null,
    "runs": [
      {"date": "2026-05-19T08:00:00Z", "new_items": 14, "checklist": "runs/2026-05-19-checklist.json"},
      {"date": "2026-05-22T14:30:00Z", "new_items": 6, "checklist": "runs/2026-05-22-checklist.json"},
      {"date": "2026-05-26T09:15:00Z", "new_items": 9, "checklist": "runs/2026-05-26-checklist.json"}
    ],
    "items_added": 29,
    "output_file": "output/meetings/meeting-27.md"
  }
}
```

## Window lifecycle

| Event | What happens |
|---|---|
| First run after window closed (or cold start) | **Open new window**: `meeting_n += 1`, `opened_date = last_meeting_date or (now - 14d)`, `target_close_date = opened_date + 14d`, `output_file = output/meetings/meeting-{N}.md`. Status `open`. |
| Subsequent runs while window open | Cutoff = `opened_date` (does NOT advance). Append finds to `output_file`. Increment `runs[]`. New items dedup against `seen-items.json`. |
| `--meeting-prep` or `--close-meeting` | **Close window**: `actual_close_date = now`, status `closed`, `last_meeting_date = now`, archive `output_file → output/meetings/archive/`. Next run opens fresh window. |
| `--window-status` | Print window state, no execution. |

## Window-status / close-meeting short-circuit

- If `--window-status` flag → print `current_meeting_window` state + last 3 runs + items_added. Stop.
- If `--close-meeting` flag (no fresh briefing requested) → execute Step 7 close logic only. Stop.

## Following-list freshness check

Read `context/following-list.json` `last_following_refresh`. If `(now - last_refresh) > refresh_interval_days` (default 42), prompt user: "Following list is N days old. Refresh now? (y/n)". On `y` OR if `--refresh-following` flag set, run Step 0a (Refresh following list) before continuing. On `n`, proceed and note staleness in output header.
