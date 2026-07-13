# Pre-execution confirmation gate

Full panel and response handling for the MANDATORY confirmation gate in Step 0.7 of the main execution flow. SKILL.md cites this file by section heading; this file is self-contained.

## Table of contents

- Confirmation panel format
- Confirmation responses
- Skip-confirmation conditions
- Why the gate exists

## Confirmation panel format

Display this before any wave runs:

```text
═══ AI Briefing Plan ═══

Meeting window:    #27 (open since 2026-05-19, target close 2026-06-02)
Cutoff:            2026-05-19T00:00:00Z
Until:             2026-05-26T09:00:00Z (now)
Window age:        7 days (5 of 14 cadence remaining)
Run number:        2 in this window (previous: 14 items added)

Coverage plan:
  Wave 1   (chrome profile scan)        160 profiles (scope=all)
           - high_signal_required:      37
           - medium_signal:             31
           - leadership_low_volume:     12 (1 scroll cap)
           - low_signal_skip_default:   80 (pass --skip-low-signal to drop)
  Wave 1.5 (Twitter Advanced Search)    NOT NEEDED (window ≤7d)
  Wave 2   (Perplexity + WebSearch)     12 queries (6 providers × 2 tools)
  Wave 3   (RSS + changelogs + GH)      18 RSS + 6 HTML + 25 GH repos = 49 sources
  Wave 4   (extras)                     1 query (--extras default on)

Estimated time:    8-12 minutes
Estimated requests: ~75-90 (chrome + perplexity + websearch + webfetch + gh api)

Output:            output/meetings/meeting-27.md (append Run #2 section)
                   output/meetings/latest.md (updated)
Run checklist:     context/runs/2026-05-26-checklist.json

Standing defaults applied:
  - thorough-date-scan (posts force-scroll)
  - retry-blocked (screenshot fallback)
  - checkpoint every 5 profiles
  - 2-profile cap per browser_batch
  - EXTRAS on
  - scope=all (every bucket — relevance filter applied at S4 categorize)
  - NO slides (markdown only — pass --format slides to override)

Proceed? [y / n / edit]
═══════════════════════
```

## Confirmation responses

| Response | Action |
|---|---|
| `y` / `yes` / Enter | Proceed to Step 1 (Wave 1 starts) |
| `n` / `no` | Cancel — preserve checklist for next session |
| `edit` | Open interactive edit: change scope flags, providers, profiles. After edit, re-display plan and re-confirm. |
| `--skip-low-signal` quick toggle | Re-display plan dropping low_signal_skip_default |
| `--no-extras` quick toggle | Re-display plan without Wave 4 |

## Skip-confirmation conditions

- `--yes` / `-y` flag → bypass confirmation (for `/loop`, `/schedule`, autonomous runs)
- Detected non-interactive context (`CLAUDE_CODE_REMOTE=true`, `<<autonomous-loop>>` sentinel, `claude -p`) → auto-confirm with note in output header

## Why the gate exists

- Multi-run meeting windows mean each run adds to existing output — user should know exactly what's about to happen before commit
- Surfaces estimated time/requests so user can defer if rate-limit-budget is tight
- Catches mismatched flags early (e.g., user expects 14d but window opened only 3d ago)
- Lets user inspect the coverage plan and add/remove profiles before burning requests
