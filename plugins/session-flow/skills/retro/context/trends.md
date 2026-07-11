# Trends Mode — Cross-Session Performance Analysis

Analyze historical session health scores to identify patterns, improvements, and areas needing
attention. No current-session analysis — purely retrospective across sessions.

## Data source

Score history persisted by session/quick mode:

```text
${CLAUDE_PLUGIN_DATA}/scores/<project-slug>.md
```

Format: `| Date | Session | Type | Workflow | Technical | Alignment | Efficiency | Errors | Overall |`

## Process

### 1. Load and parse the score history

If the file doesn't exist, report "No historical scores found. Run `/retro session` to build
history." and exit.

### 2. Compute aggregate statistics

| Dimension | Mean | Median | Min | Max | Trend (last 10) |
|-----------|------|--------|-----|-----|-----------------|
| Workflow | | | | | improving/stable/declining |
| Technical | | | | | |
| Alignment | | | | | |
| Efficiency | | | | | |
| Errors | | | | | |
| **Overall** | | | | | |

### 3. Identify patterns

- **Strongest dimensions** — consistently 8+, established habits
- **Weakest dimensions** — consistently below 7, need focus
- **Volatility** — high variance suggests inconsistent application
- **Session type correlation** — do scores vary by session type?
- **Time trends** — improving, stable, or declining over the recorded span?

### 4. Generate actionable insights

Suggest 2-3 specific focus areas for the next session:

| # | Focus area | Evidence | Suggested action |
|---|-----------|----------|-----------------|

### 5. Notable sessions

Highlight outliers — best sessions (overall 9+, what made them great) and worst (overall <6, what
went wrong).

## What this mode does NOT do

- No current-session analysis, no transcript metrics
- No memory writes or rule edits
- No skill/follow-up candidate generation

It's analytical: load data, find patterns, suggest focus areas.
