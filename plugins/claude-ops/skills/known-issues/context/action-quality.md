# Action: `quality`

**Usage:** `/claude-ops:known-issues quality`

Check current Claude model quality and service health from multiple sources. Use at start of work sessions or when you notice degraded performance.

## Sources (checked in order)

**Source 1: [Marginlab Performance Tracker](https://marginlab.ai/trackers/claude-code/).** Our model-performance signal: an independent daily benchmark tracker. Its benchmark, sample size and significance method are stated on the page; read them there.

Fetch via WebFetch or curl and extract:

- Degradation status (Nominal / Degraded / Significantly Degraded)
- Today's pass rate vs 7-day and 30-day averages
- Statistical significance of any delta

**Source 2: [status.claude.com](https://status.claude.com/).** Our service-health signal: the official status page, read per component.

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

A sudden quality change mid-session can be a model switch, not a regression. Before blaming the
model, check the transcript for a notice that the session moved to a fallback model after a
flagged message. To recover, we use:

- `/model` to switch back to the original model.
- `/config` > **Switch models when a message is flagged** off (or `switchModelsOnFlag: false`)
  to be asked each time instead of switched.
- `/feedback` to report a flag that looks wrong.

Pointer: for the fallback behavior and the recovery settings, see
[Automatic model fallback](https://code.claude.com/docs/en/model-config#automatic-model-fallback)
(correlate with the [Opus 5.5 usage guide](https://claude.dev/blog/getting-the-most-out-of-opus-5-5/)).
As of: 2026-09-23. Recheck trigger: that section changes, or a new model gains or loses a
fallback.

## Fragility note

Marginlab and status.claude.com embed data as JavaScript objects, not REST APIs. HTML scraping via WebFetch is the only option. If either source changes page structure, extraction breaks. Fall back to manual browser check and note breakage for repair. Add to quarterly drift check.
