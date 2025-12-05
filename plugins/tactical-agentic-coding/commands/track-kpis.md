# Track KPIs

Calculate and update agentic coding KPIs to measure ZTE progression.

## Arguments

- `$ARGUMENTS`: State context containing ADW ID, issue info, and workflow history

## Instructions

You are updating the agentic KPI tracking file to measure workflow effectiveness.

### Step 1: Parse State

Extract from arguments or current context:

- `adw_id`: Workflow identifier
- `issue_number`: GitHub issue number
- `issue_class`: Classification (`/chore`, `/bug`, `/feature`)
- `plan_file`: Path to implementation plan
- `all_adws`: List of workflows run (for attempts calculation)

### Step 2: Calculate Attempts

Count only workflows that represent restarts:

```python
attempts_incrementing = ["adw_plan_iso", "adw_patch_iso", "plan", "patch"]
attempts = count(workflow for workflow in all_adws if any(inc in workflow for inc in attempts_incrementing))
```markdown

Build, test, review don't count - only full replans.

### Step 3: Get Plan Size

```bash
wc -l {plan_file}
```markdown

Extract line count as plan_size.

### Step 4: Get Diff Statistics

```bash
git diff origin/main --shortstat
```markdown

Parse output to extract:

- Files changed
- Lines added (+)
- Lines removed (-)

### Step 5: Update Detail Table

Add new row to the KPI detail table:

| Date | ADW ID | Issue | Class | Attempts | Plan Size | Diff +/- | Files |
| ------ | -------- | ------- | ------- | ---------- | ----------- | ---------- | ------- |
| {today} | {adw_id} | #{issue_number} | {issue_class} | {attempts} | {plan_size} | +{added}/-{removed} | {files} |

### Step 6: Recalculate Summary

**Current Streak:** Count consecutive rows from bottom where Attempts <= 2

**Longest Streak:** Find longest consecutive sequence where Attempts <= 2

**Average Presence:** Mean of all attempts values

**Total Plan Size:** Sum of all plan_size values

**Total Diff Size:** Sum of (added + removed) across all runs

### Step 7: Update KPI File

Write updated summary and detail tables to the KPI file (typically `app_docs/agentic_kpis.md` or project-specific location).

## Output

Report KPI update:

```json
{
  "success": true,
  "this_run": {
    "adw_id": "{adw_id}",
    "issue": "{issue_number}",
    "attempts": 1,
    "plan_size": 45,
    "diff_added": 67,
    "diff_removed": 23,
    "files_changed": 4
  },
  "summary": {
    "current_streak": 6,
    "longest_streak": 12,
    "average_presence": 1.28,
    "total_plan_size": 450,
    "total_diff_size": 2340
  }
}
```markdown

## Notes

- Lower attempts = better (target: 1)
- Higher streak = better (demonstrates consistency)
- Track trends over time to assess ZTE readiness
- 90%+ success rate (attempts <= 2) indicates ZTE readiness
