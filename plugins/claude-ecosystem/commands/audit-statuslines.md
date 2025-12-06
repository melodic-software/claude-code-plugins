---
description: Audit Claude Code status line configurations for quality and cross-platform compatibility
argument-hint: [--force] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(test:*), Glob, Task, Skill
---

# Audit Status Lines Command

You are tasked with auditing Claude Code status line configurations for quality and cross-platform compatibility.

## What Gets Audited

This command audits:

- Script structure and execution
- JSON input handling
- Terminal color code usage
- Cross-platform compatibility (Windows, macOS, Linux)
- Helper function usage

## Command Arguments

This command accepts **flags** as arguments:

- **No arguments**: Audit all discoverable status line scripts
- **--force**: Audit regardless of modification status

## Step 0: Get Current Date (REQUIRED)

```bash
date -u +"%Y-%m-%d"
```

## Step 1: Discover Status Line Configurations

### Detection Algorithm

Status lines are configured in settings.json and point to script files:

```bash
# Check project settings for statusLine setting
if [ -f ".claude/settings.json" ]; then
    grep -o '"statusLine"[[:space:]]*:[[:space:]]*"[^"]*"' .claude/settings.json
fi

# Check user settings for statusLine setting
if [ -f "$HOME/.claude/settings.json" ]; then
    grep -o '"statusLine"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.claude/settings.json"
fi
```

### Build Status Line List

```text
statuslines = []

# Parse statusLine settings from project and user settings.json
for each settings_file in [".claude/settings.json", "~/.claude/settings.json"]:
  if exists(settings_file):
    statusLine = parse_json(settings_file).statusLine
    if statusLine:
      statuslines.append({
        scope: "project" or "user",
        script_path: statusLine,
        settings_file: settings_file
      })
```

### Handle No Status Lines

If no custom status lines are configured, report this and exit gracefully:

```markdown
## Status Line Audit

No custom status lines are configured in this project or user settings.

To configure a custom status line:
1. Create a script that accepts JSON input via stdin
2. Add `"statusLine": "/path/to/script"` to your settings.json
```

## Step 2: Parse Arguments

1. Parse flags (--force)
2. Build status line list

## Step 3: Present Audit Plan

```markdown
## Audit Plan

**Mode**: {SMART/FORCE}
**Status line scripts discovered**: X

### Scripts to Audit:
1. [project] /path/to/statusline.sh (last modified: YYYY-MM-DD)
2. [user] ~/scripts/my-statusline.py (last modified: YYYY-MM-DD)
...

Proceeding with audit...
```

## Step 4: Execute Audits

### For Each Status Line Script

1. **Invoke statusline-auditor subagent**:

   ```text
   Use the statusline-auditor subagent to audit the status line script.

   Context:
   - Scope: {project/user}
   - Script path: {full path}
   - Settings file: {which settings.json references it}

   The subagent auto-loads status-line-customization skill and handles the audit.
   ```

2. Wait for completion
3. Report results

### Parallel Execution

If multiple status lines, audit in parallel (one subagent per script).

## Step 5: Final Summary

```markdown
## Status Line Audit Complete

**Total audited**: X status line scripts
**By scope**:
- Project: Y scripts
- User: Z scripts

**Results**:
- Passed: A scripts
- Passed with warnings: B scripts
- Failed: C scripts

### Details

| Scope | Script | Result | Score |
|-------|--------|--------|-------|
| project | statusline.sh | PASS | 90/100 |
| user | my-statusline.py | PASS WITH WARNINGS | 72/100 |

**Cross-Platform Issues**:
- [List any platform-specific issues]

**JSON Handling Issues**:
- [List any JSON parsing issues]

**Next Steps**:
- Fix cross-platform compatibility issues
- Improve JSON input handling
- Add proper error handling
- Re-audit after changes
```

## Important Notes

### Script Requirements

Status line scripts must:

1. Accept JSON input via stdin
2. Parse the JSON structure correctly
3. Output formatted text for terminal display
4. Work across Windows, macOS, and Linux

### JSON Input Structure

The JSON input includes:

- Model information
- Workspace details
- Cost tracking
- Session information

### Terminal Color Codes

If using terminal colors:

- Use ANSI escape codes correctly
- Provide fallbacks for terminals without color support
- Test on multiple terminal emulators

### Cross-Platform Compatibility

Scripts should work on:

- **Bash** (Linux, macOS, Git Bash on Windows)
- **Python** (cross-platform)
- **Node.js** (cross-platform)

Avoid platform-specific features without fallbacks.

### Helper Functions

Common helper functions include:

- JSON parsing (jq, python json, etc.)
- Color code generation
- Git status integration

Verify helper functions are available or have fallbacks.
