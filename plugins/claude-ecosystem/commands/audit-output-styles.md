---
description: Audit Claude Code output styles for quality, compliance, and usability
argument-hint: [project | user | all] [--force] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(test:*), Glob, Task, Skill
---

# Audit Output Styles Command

You are tasked with auditing Claude Code output styles for quality, compliance, and usability.

## What Gets Audited

This command audits:

- Markdown file format
- YAML frontmatter (name, description, keep-coding-instructions)
- Content structure and clarity
- File naming conventions
- Style switching compatibility

## Command Arguments

This command accepts **scope selectors and/or flags** as arguments:

- **No arguments**: Audit all discoverable output styles
- **project**: Audit only `.claude/output-styles/*.md`
- **user**: Audit only `~/.claude/output-styles/*.md`
- **all**: Audit all output styles (project + user)
- **--force**: Audit regardless of modification status

**Argument format**:

- Scope first (e.g., `project`, `user`, `all`)
- Flags last: `--force` (case-insensitive)

## Step 0: Get Current Date (REQUIRED)

```bash
date -u +"%Y-%m-%d"
```

## Step 1: Discover Output Styles

### Detection Algorithm

```bash
# Check for project output styles
if [ -d ".claude/output-styles" ]; then
    echo "Project output styles:"
    ls -la .claude/output-styles/*.md 2>/dev/null
fi

# Check for user output styles
if [ -d "$HOME/.claude/output-styles" ]; then
    echo "User output styles:"
    ls -la "$HOME/.claude/output-styles"/*.md 2>/dev/null
fi
```

### Build Output Style List

```text
output_styles = []

if scope == "project" or scope == "all" or no_scope:
  for each file in ".claude/output-styles/*.md":
    output_styles.append({
      scope: "project",
      path: file_path,
      name: filename_without_extension
    })

if scope == "user" or scope == "all":
  for each file in "~/.claude/output-styles/*.md":
    output_styles.append({
      scope: "user",
      path: file_path,
      name: filename_without_extension
    })
```

### Apply Scope Filter

Based on arguments, filter to requested scope(s).

## Step 2: Parse Arguments

1. Parse scope selector from arguments
2. Parse flags (--force)
3. Build filtered output style list

## Step 3: Present Audit Plan

```markdown
## Audit Plan

**Mode**: {SMART/FORCE}
**Output styles discovered**: X

### Files to Audit:
1. [project] .claude/output-styles/concise.md (last modified: YYYY-MM-DD)
2. [user] ~/.claude/output-styles/verbose.md (last modified: YYYY-MM-DD)
...

Proceeding with audit...
```

## Step 4: Execute Audits

### Parallel Batching Strategy

Group output styles into batches of **3-5** for parallel auditing:

```text
batches = chunk(output_styles, 5)

for batch in batches:
  # Spawn parallel subagents for this batch
  for style in batch:
    spawn output-style-auditor subagent
  wait_for_all_in_batch()
```

### For Each Output Style

1. **Invoke output-style-auditor subagent**:

   ```text
   Use the output-style-auditor subagent to audit the output style.

   Context:
   - Scope: {project/user}
   - File path: {full path}
   - Style name: {name from file}

   The subagent auto-loads output-customization skill and handles the audit.
   ```

2. Wait for batch completion
3. Report results

## Step 5: Final Summary

```markdown
## Output Style Audit Complete

**Total audited**: X output styles
**By scope**:
- Project: Y styles
- User: Z styles

**Results**:
- Passed: A styles
- Passed with warnings: B styles
- Failed: C styles

### Details

| Scope | Style | Result | Score |
|-------|-------|--------|-------|
| project | concise | PASS | 92/100 |
| user | verbose | PASS WITH WARNINGS | 75/100 |

**Common Issues Found**:
- [List common issues across multiple styles]

**Recommendations**:
- [Specific improvements to make]

**Next Steps**:
- Fix missing frontmatter fields
- Improve content structure
- Re-audit after changes
```

## Important Notes

### Frontmatter Requirements

Output styles require YAML frontmatter with:

- `name`: Display name for the style
- `description`: What this style does
- `keep-coding-instructions`: Boolean (optional)

### File Naming

- Use kebab-case: `my-style.md`
- Must be `.md` extension
- Name should be descriptive

### Built-in Styles

Claude Code includes built-in styles (Default, Explanatory, Learning). Custom styles should not conflict with or duplicate these.

### Style Switching

Output styles are selected via `/output-style` command. Verify styles work correctly with style switching.
