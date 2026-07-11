# Action: `quality`

**Usage:** `/claude-troubleshooting quality`

Check current Claude model quality and service health from multiple sources. Use at start of work sessions or when you notice degraded performance.

## Sources (checked in order)

**Source 1: [Marginlab Performance Tracker](https://marginlab.ai/trackers/claude-code/)** — Independent daily benchmarks on SWE-Bench-Pro. Updated daily, 50 evals/day. Statistical significance testing (p < 0.05).

Fetch via WebFetch or curl and extract:

- Degradation status (Nominal / Degraded / Significantly Degraded)
- Today's pass rate vs 7-day and 30-day averages
- Statistical significance of any delta

**Source 2: [status.claude.com](https://status.claude.com/)** — Official Anthropic status page. Covers claude.ai, API, Claude Code, platform.

Fetch and extract:

- Overall status (Operational / Degraded / Outage)
- Per-component status
- Active incidents in last 48 hours

**Source 3: GitHub degradation reports** — Search recent community-reported quality issues:

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

## Fragility note

Marginlab and status.claude.com embed data as JavaScript objects, not REST APIs. HTML scraping via WebFetch is the only option. If either source changes page structure, extraction breaks — fall back to manual browser check and note breakage for repair. Add to quarterly drift check.

## Additional sources (not yet integrated)

- [zscole/ai-poc-model-tracker](https://github.com/zscole/ai-poc-20260131-model-tracker) — open-source degradation tracker with statistical testing. Python-based, could be forked for local monitoring
- Anthropic may publish daily benchmark snapshots (articles reference a "public dashboard" but URL not verified). Check periodically.
- [StatusGator](https://statusgator.com/services/claude) and [IsDown](https://isdown.app/status/anthropic) — third-party status aggregators
