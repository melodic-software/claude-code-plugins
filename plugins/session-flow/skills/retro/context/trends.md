# Trends Mode: Cross-Session Performance Analysis

Analyze historical session health scores to identify patterns, improvements, and areas needing
attention. No current-session analysis; purely retrospective across sessions.

## Data source

Score history persisted by session/quick mode: the file SKILL.md "Paths" names, `<project-slug>.md`.

Format: `| Date | Session | Type | Workflow | Technical | Alignment | Efficiency | Errors | Overall |`

Delivery metrics, when available, come from `/work-items:measure-delivery` (step 6), which reads the
default branch's git history.

## Process

### 1. Load and parse the score history

If the file doesn't exist, report "No historical scores found. Run `/session-flow:retro session` to build
history." and skip to step 6.

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

- **Strongest dimensions.** Consistently 8+, established habits
- **Weakest dimensions.** Consistently below 7, need focus
- **Volatility.** High variance suggests inconsistent application
- **Session type correlation.** Do scores vary by session type?
- **Time trends.** Improving, stable, or declining over the recorded span?

### 4. Generate actionable insights

Suggest 2-3 specific focus areas for the next session:

| # | Focus area | Evidence | Suggested action |
|---|-----------|----------|-----------------|

### 5. Notable sessions

Highlight outliers: best sessions (overall 9+, what made them great) and worst (overall <6, what
went wrong).

### 6. Delivery metrics

When `/work-items:measure-delivery` is among the available skills, invoke it through the Skill tool
with no arguments, and show its whole report (the table, the trend lines, and the window, branch
and deploy-signal lines) under a `Delivery metrics` heading after the score trends. When it stops
on an error or asks for `--branch`, show that line in place of its report and finish this one. When
the skill is not among the available skills, say "Delivery metrics: `/work-items:measure-delivery`
is not among the available skills (install or enable the work-items plugin)." The step is done
when its report, that line or that sentence is shown.

## What this mode does NOT do

- No current-session analysis, no transcript metrics
- No memory writes or rule edits
- No skill/follow-up candidate generation
- No delivery metrics of its own; they come only from `/work-items:measure-delivery`

It's analytical: load data, find patterns, suggest focus areas.
