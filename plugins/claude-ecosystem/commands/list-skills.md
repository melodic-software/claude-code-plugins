---
description: List all available Skills with their descriptions
allowed-tools: Bash, Glob
---

# List Skills

List ALL available Claude Code skills by running the list_skills.py script.

## Step 1: Find the Script

Locate list_skills.py in the claude-ecosystem plugin:

```bash
# Check installed plugins first
find ~/.claude/plugins -name "list_skills.py" -path "*claude-ecosystem*" 2>/dev/null | head -1
```

If not found, check current repo (for development):

```bash
find . -name "list_skills.py" -path "*claude-ecosystem*" 2>/dev/null | head -1
```

## Step 2: Run the Script

Execute with Python using the path found in Step 1:

```bash
python "<found-path>/list_skills.py"
```

## What the Script Scans

The script finds ALL skills from:

- **Personal skills**: `~/.claude/skills/*/SKILL.md`
- **Project skills**: `.claude/skills/*/SKILL.md` (current working directory)
- **Plugin skills**: `~/.claude/plugins/marketplaces/*/*/skills/*/SKILL.md`

## Output Format

The script outputs formatted markdown:

```text
## Personal Skills (~/.claude/skills/)
### **skill-name**
Description from SKILL.md frontmatter.
---

## Project Skills (.claude/skills/)
### **skill-name**
Description from SKILL.md frontmatter.
---

## Plugin Skills
### **plugin-name:skill-name**
Description from SKILL.md frontmatter.
---

**Total: X skills** (Y personal, Z project, W plugin)
```

Output the script results directly - they are already formatted.
