---
allowed-tools: Write, Bash(mkdir:*), Skill
argument-hint: [skill-name]
description: Create new skill scaffold with required structure
---

# Create Skill

Create a new skill scaffold with required structure.

## Skill Name

$ARGUMENTS

## Instructions

1. Invoke the `claude-ecosystem:skills-meta` skill to get:
   - Skill naming conventions
   - Required YAML frontmatter
   - Directory structure requirements
   - Best practices

2. Create the skill scaffold:
   - `.claude/skills/$ARGUMENTS/SKILL.md` with proper frontmatter
   - Reference subdirectory structure if needed

3. Follow the established patterns from existing skills in this repo.
