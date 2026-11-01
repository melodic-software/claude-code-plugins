# Trends Mode: Cross-Session Performance Analysis

Analyze historical session health scores to identify patterns, improvements, and areas needing
attention, and show the team's delivery metrics beside them when the work-items plugin is installed.
No current-session analysis; purely retrospective across sessions.

## Data source

Score history persisted by session/quick mode: the file SKILL.md "Paths" names, `<project-slug>.md`.

Format: `| Date | Session | Type | Workflow | Technical | Alignment | Efficiency | Errors | Overall |`

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
with no arguments, which reads the default 84-day window in weekly buckets. Show its table and trend
lines under a `Delivery` heading, with the window, branch and deploy signal it reports and its
note that the history runs up to the last fetch. They
describe the team's delivery from the default branch's history, so keep them in their own table,
apart from the session score statistics. Keep its rule of never naming a person.

When the skill is not among the available skills (the work-items plugin is not installed), write
"Delivery metrics: not read, `/work-items:measure-delivery` is not available in this session."
under that heading. When the skill runs and stops on an error, put its error line there instead;
when it stops because `origin/HEAD` is unset, also name `--branch` as the fix the person can rerun
it with. The step is done when the `Delivery` heading holds the table, the not-read line or the error line.

## What this mode does NOT do

- No current-session analysis, no transcript metrics
- No memory writes or rule edits
- No skill/follow-up candidate generation

It's analytical: load data, find patterns, suggest focus areas, show delivery metrics.
