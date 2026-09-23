# Action: `quality`

**Usage:** `/claude-ops:known-issues quality`

Check current Claude model quality and service health from multiple sources. Use at start of work sessions or when you notice degraded performance.

## Sources (checked in order)

**Source 1: [Marginlab Performance Tracker](https://marginlab.ai/trackers/claude-code/).** Independent daily benchmarks on SWE-Bench-Pro. Updated daily, 50 evals/day. Statistical significance testing (p < 0.05).

Fetch via WebFetch or curl and extract:

- Degradation status (Nominal / Degraded / Significantly Degraded)
- Today's pass rate vs 7-day and 30-day averages
- Statistical significance of any delta

**Source 2: [status.claude.com](https://status.claude.com/).** Official Anthropic status page. Covers claude.ai, API, Claude Code, platform.

Fetch and extract:

- Overall status (Operational / Degraded / Outage)
- Per-component status
- Active incidents in last 48 hours

**Source 3: GitHub degradation reports.** Search recent community-reported quality issues:

```bash
gh search issues "degraded OR degradation OR quality OR nerfed OR slower" --repo anthropics/claude-code --state open --sort updated --limit 10 --json number,title,updatedAt
```

## Output format

```markdown
## Claude Quality Check (YYYY-MM-DD HH:MM)

### Model Performance (Marginlab)
- **Status**: Nominal / Degraded / Significantly Degraded
- **Today**: X% pass rate (N evals)
- **7-day**: X% | **30-day**: X% | **Baseline**: X%
- **Delta**: +/-X% (significant/not significant)

### Service Health (status.claude.com)
- **Overall**: Operational / Degraded / Outage
- **Claude Code**: Status (X% uptime)
- **Active incidents**: None / Description

### Community Reports
- N recent degradation reports in last 7 days
- Most recent: #NNNNN "title" (date)

### Recommendation
- **ALL CLEAR**: Quality nominal, services operational. Proceed normally.
- **QUALITY WARNING**: Marginlab shows degradation. Consider: simpler prompts, more verification, expect rework.
- **SERVICE ISSUE**: Active incident on status page. Check if it affects your workflow.
- **DEGRADED**: Both quality and service issues. Consider deferring complex work.
```

## Before blaming the model: check for a flag fallback

A sudden quality change mid-session can be a model switch, not a regression. When a safety
classifier flags a request (most often cybersecurity or biology content), Claude Code re-runs it
on an older fallback model, shows a notice naming that model in the transcript, and the session
stays on it. Check the transcript for that notice first. To recover:

- `/model` switches back to the original model.
- `/config` > **Switch models when a message is flagged** off (or `switchModelsOnFlag: false`)
  asks each time instead of switching.
- If the flag looks wrong, report it with `/feedback` (vendor-reported advice, from the
  [Opus 5.5 usage guide](https://claude.dev/blog/getting-the-most-out-of-opus-5-5/)).

Verification: claim, the fallback behavior and the two recovery settings above; basis, the
[model-config page, "Automatic model fallback"](https://code.claude.com/docs/en/model-config);
as of 2026-09-23; recheck when that section changes or a new model gains or loses a fallback.

## Fragility note

Marginlab and status.claude.com embed data as JavaScript objects, not REST APIs. HTML scraping via WebFetch is the only option. If either source changes page structure, extraction breaks. Fall back to manual browser check and note breakage for repair. Add to quarterly drift check.
