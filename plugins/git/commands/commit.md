---
description: Create a git commit using Conventional Commits format with safety protocols
allowed-tools: Read, Bash, Skill
---

# Commit Command

Create a git commit following all safety protocols, using Conventional Commits format with proper attribution.

## Instructions

**Use the git:git-commit skill to handle the complete commit workflow.**

The git:git-commit skill provides:

- **Conventional Commits format** with Claude Code attribution
- **Intelligent staging decisions** - handles mixed staged/unstaged scenarios
- **Safety protocols** (all NEVER rules enforced)
- **4-step workflow** (gather → analyze → execute → handle hooks)
- **Pre-commit hook handling** with amend safety checks
- **Verification steps** before committing

**Simply invoke the skill and follow its complete workflow:**

```text
Use the git:git-commit skill to create a commit.

Follow the skill's 4-step workflow:
1. Gather information (git status, git diff, git log)
2. Determine what to commit (handles staging decisions intelligently)
3. Execute commit with HEREDOC format
4. Handle pre-commit hook failures if needed

The skill contains all safety protocols and commit formatting requirements.
```

## How Staging is Handled

The skill intelligently handles different staging scenarios:

- **Nothing to commit**: Exits gracefully with "working tree clean" message
- **Files already staged**: Proceeds directly with staged files (user has pre-staged what they want)
- **Nothing staged, but changes exist**: Asks whether to stage all or let you choose specific files
- **Mixed (some staged, some not)**: Asks whether to commit only staged files or include everything

You don't need to worry about staging - the skill will guide you through the right choice.

## IMPORTANT

Do NOT bypass the skill and run git commands directly. The git:git-commit skill ensures:

- Conventional Commits format compliance
- Intelligent staging decisions with user confirmation
- Safety verification (secrets, absolute paths, system changes)
- Proper attribution footer
- Pre-commit hook handling
- All NEVER rules enforced

Let the skill guide the complete workflow.
