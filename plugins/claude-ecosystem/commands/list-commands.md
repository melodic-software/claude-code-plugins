---
description: List all custom slash commands with their descriptions
model: claude-haiku-4-5-20251001
allowed-tools: Bash(grep:*), Bash(wc:*), Bash(ls:*), Bash(test:*)
---

# List Commands

List all custom slash commands from the current repository using efficient single-pass extraction.

## Step 1: Detect Repository Type

Determine which command directories to search:

```bash
# Check for marketplace repo
if [ -f "marketplace.json" ] || [ -f ".claude-plugin/marketplace.json" ]; then
    echo "REPO_TYPE=marketplace"
fi

# Check for plugin repo
if [ -f ".claude-plugin/plugin.json" ] && [ -d "./commands" ]; then
    echo "REPO_TYPE=plugin"
fi

# Check for project commands
if [ -d ".claude/commands" ]; then
    echo "HAS_PROJECT_COMMANDS=true"
fi
```

## Step 2: Search Appropriate Directories

Based on repo type, search the correct directories:

**For marketplace repos:**

```bash
# Search all plugin command directories + project commands
grep -r "^description:" plugins/*/commands --include="*.md" 2>/dev/null | sort
grep -r "^description:" .claude/commands --include="*.md" 2>/dev/null | sort
```

**For plugin repos:**

```bash
# Search plugin commands + project commands
grep -r "^description:" ./commands --include="*.md" 2>/dev/null | sort
grep -r "^description:" .claude/commands --include="*.md" 2>/dev/null | sort
```

**For standard repos:**

```bash
# Search project commands only
grep -r "^description:" .claude/commands --include="*.md" 2>/dev/null | sort
```

## Step 3: Format Output

Parse the grep output and format as:

```text
### Plugin Commands ({plugin-name})

### **/command-name**
Description from frontmatter

---

### Project Commands

### **/command-name**
Description from frontmatter

---
```

## Output Requirements

- Group commands by source (plugin vs project)
- Use bold markdown for command names (### **/name**)
- Add horizontal rule separator (---) between commands
- Keep descriptions concise
- Show total count at the end by source
- Sort commands alphabetically within each group

## When Subagent Pattern Makes Sense

For larger operations (50+ files, complex per-file analysis), consider:

1. One agent to discover all files
2. Divide into groups of ~10-15 files
3. Parallel subagents to process each group
4. Main agent aggregates results

This pattern adds ~2-3s overhead per subagent, so only use when per-item processing time justifies it.
