---
description: View skill audit log entries
argument-hint: [plugin:name | project | all] (optional)
allowed-tools: Read, Grep, Bash(ls:*), Bash(test:*)
---

# Audit Log

View skill audit log entries from all discovered sources in the repository.

## Arguments

- **No argument** or **all**: Show unified view of all audit logs
- **project**: Show only project skill audit log (`.claude/skills/.audit-log.md`)
- **plugin:{name}**: Show audit log for specific plugin (e.g., `plugin:claude-ecosystem`)

## Step 1: Discover Audit Log Sources

Detect all audit logs in the current repository:

```bash
# Check for marketplace repo
if [ -f "marketplace.json" ] || [ -f ".claude-plugin/marketplace.json" ]; then
    # Find all plugin audit logs
    for plugin_dir in plugins/*/; do
        if [ -f "${plugin_dir}skills/.audit-log.md" ]; then
            echo "PLUGIN_LOG: ${plugin_dir}skills/.audit-log.md"
        fi
    done
fi

# Check for single plugin repo
if [ -f ".claude-plugin/plugin.json" ] && [ -f "./skills/.audit-log.md" ]; then
    echo "PLUGIN_LOG: ./skills/.audit-log.md"
fi

# Check for project audit log
if [ -f ".claude/skills/.audit-log.md" ]; then
    echo "PROJECT_LOG: .claude/skills/.audit-log.md"
fi
```

## Step 2: Read and Display Logs

Based on argument, read and display appropriate logs:

### Unified View (no arg or "all")

```markdown
# Skill Audit Log Summary

## Plugin: {plugin-name}
**Location**: {path}/skills/.audit-log.md

| Skill | Last Audit |
| ----- | ---------- |
| skill-1 | 2025-11-30 |
| skill-2 | 2025-11-28 |

**Stats**: X skills, Y audited, Z need re-audit (>90 days)

---

## Project Skills
**Location**: .claude/skills/.audit-log.md

| Skill | Last Audit |
| ----- | ---------- |
| skill-1 | 2025-11-30 |
| skill-2 | Never |

**Stats**: X skills, Y audited, Z need re-audit

---

## Summary

**Total skills tracked**: X
**Recently audited (<90 days)**: Y
**Need re-audit (>90 days or never)**: Z
```

### Filtered View (specific source)

If argument is `project` or `plugin:{name}`, show only that source's log with full detail.

## Step 3: Analysis

For each audit log, calculate and report:

1. **Total skills** in the log
2. **Recently audited** (within last 90 days)
3. **Need re-audit** (>90 days old or never audited)
4. **Most stale** (longest since last audit)
5. **Never audited** (no audit date)

## Output Format

```markdown
# Audit Log: {source}

## Current Status

| Skill | Last Audit | Status |
| ----- | ---------- | ------ |
| skill-name | 2025-11-30 | Recent |
| skill-name | 2025-08-15 | Stale (107 days) |
| skill-name | - | Never audited |

## Statistics

- **Total skills**: X
- **Recently audited** (<90 days): Y
- **Need attention**: Z
  - Stale (>90 days): A
  - Never audited: B

## Recommendations

Skills due for re-audit (oldest first):
1. skill-name (last audit: 2025-08-15, 107 days ago)
2. skill-name (never audited)
3. ...

Run `/audit-skills {skill-name}` to audit specific skills.
Run `/audit-skills --force` to audit all skills.
```

## Error Handling

If no audit logs found:

```markdown
# No Audit Logs Found

No skill audit logs were found in this repository.

**Checked locations**:
- .claude/skills/.audit-log.md (not found)
- plugins/*/skills/.audit-log.md (not found)
- ./skills/.audit-log.md (not found)

**To create audit logs**, run `/audit-skills` to audit your skills.
Audit logs are created automatically when skills are audited.
```

If specific source not found:

```markdown
# Audit Log Not Found: {source}

The requested audit log was not found.

**Available sources**:
- project (.claude/skills/.audit-log.md)
- plugin:claude-ecosystem (plugins/claude-ecosystem/skills/.audit-log.md)

Use one of the available sources or run `/audit-log all` for unified view.
```
