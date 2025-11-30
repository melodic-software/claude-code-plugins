---
name: git-commit
description: Comprehensive Git commit workflow using Conventional Commits format with safety protocols. Create, validate, and execute commits following best practices. Use when creating commits, drafting commit messages, handling pre-commit hooks, creating pull requests, or uncertain about commit safety, timing, or message format. CRITICAL - Always invoke before any commit operation - contains NEVER rules, attribution requirements, and proper message formatting.
---

# Git Commit

Comprehensive Git commit protocol implementing Conventional Commits specification with strict safety rules, proper attribution, and complete workflow guidance.

## Table of Contents

- [Overview](#overview)
- [When to Use This Skill](#when-to-use-this-skill)
- [Critical Safety Rules (NEVER)](#critical-safety-rules-never)
- [Conventional Commits Format](#conventional-commits-format)
- [Commit Workflow (4 Steps)](#commit-workflow-4-steps)
- [Pull Request Creation](#pull-request-creation)
- [When to Commit](#when-to-commit)
- [System Changes Documentation](#system-changes-documentation)
- [Examples](#examples)
- [Resources](#resources)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Testing](#testing)
- [Version History](#version-history)

## Overview

This skill provides the authoritative protocol for all Git commit operations, including:

- **Conventional Commits format** with required attribution footer
- **Intelligent staging decisions** handling mixed staged/unstaged scenarios
- **Safety rules** preventing destructive operations
- **4-step commit workflow** ensuring proper execution
- **Pre-commit hook handling** for automated tooling failures
- **Pull request creation** with complete context
- **System changes verification** before committing

**CRITICAL**: This skill must be invoked before ANY commit operation to ensure compliance with safety protocols and message formatting requirements.

## When to Use This Skill

This skill should be used when:

- Creating any Git commit (regular, initial, merge)
- Drafting commit messages following Conventional Commits
- Handling pre-commit hook failures or modifications
- Creating pull requests with `gh pr create`
- Uncertain about commit timing (when to commit vs when to wait)
- Validating commit safety (checking for secrets, absolute paths, etc.)
- Amending commits (rare - requires safety checks)
- Verifying system changes documentation before committing

**IMPORTANT**: Only create commits when the user explicitly requests. If unclear, ask first.

## Critical Safety Rules (NEVER)

These rules are non-negotiable and MUST be followed:

### NEVER Rules

1. **NEVER update git config** - Configuration changes must be intentional and user-approved
2. **NEVER run destructive commands** - No `git push --force`, `git reset --hard`, etc. unless explicitly requested
3. **NEVER skip hooks** - No `--no-verify` or `--no-gpg-sign` flags unless explicitly requested by user
4. **NEVER force push to main/master** - Warn user if they request this
5. **NEVER use `git commit --amend`** - ONLY permitted when:
   - User explicitly requests amend, OR
   - Pre-commit hook modified files (requires safety checks - see [Hook Handling](#step-4-handle-pre-commit-hook-failures))
6. **NEVER commit without explicit user request** - This is VERY IMPORTANT - only commit when user asks
7. **NEVER commit secret files** - Do not commit `.env`, `credentials.json`, etc. - warn user if requested
8. **NEVER use interactive git commands** - No `-i` flags (`git rebase -i`, `git add -i`) - not supported in non-interactive environments

### Safety Verification Before Committing

Before executing any commit:

- ✅ **Check for secrets** - Scan staged files for common secret patterns
- ✅ **Check for absolute paths** - Ensure no machine-specific paths (like `D:\repos\...`, `/home/user/...`)
- ✅ **Verify SYSTEM-CHANGES.md** - If any files outside repo were modified (configs, keys, etc.), ensure documented
- ✅ **Confirm user intent** - If unclear whether to commit, ask user first

## Conventional Commits Format

All commit messages MUST follow the Conventional Commits specification with required Claude Code attribution.

### Basic Structure

```text
<type>[optional scope]: <description>

[optional body]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Commit Types

Use these standardized types:

- **feat**: New feature (correlates to MINOR in SemVer)
- **fix**: Bug fix (correlates to PATCH in SemVer)
- **docs**: Documentation changes only
- **style**: Code style changes (formatting, missing semicolons, no logic change)
- **refactor**: Code refactoring (neither fixes bug nor adds feature)
- **perf**: Performance improvements
- **test**: Adding or updating tests
- **chore**: Maintenance tasks (dependencies, tooling, configs)
- **ci**: CI/CD configuration changes
- **build**: Build system or external dependency changes

### Breaking Changes

Indicate breaking changes using EITHER:

1. **Exclamation mark** before colon: `feat!: change API response format`
2. **BREAKING CHANGE footer**: Include `BREAKING CHANGE: <description>` in message body

### Scope (Optional)

Add scope to provide context about what area of codebase is affected:

```text
feat(api): add user authentication endpoint
fix(database): resolve connection timeout issue
docs(readme): update installation instructions
```

### Message Guidelines

- **Description**: Start with lowercase, no period at end, max ~50 characters
- **Focus on WHY, not WHAT**: Explain intent and reason, not just the change
- **Be concise**: 1-2 sentences in body if needed
- **Use imperative mood**: "add feature" not "added feature" or "adds feature"

### Complete Message Example

```bash
git commit -m "$(cat <<'EOF'
feat(auth): add JWT token refresh mechanism

Implements automatic token refresh to improve user experience
and reduce unnecessary re-authentication.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

## Commit Workflow (4 Steps)

Follow this complete workflow for every commit operation.

### Step 1: Gather Information (Parallel)

Run these commands in parallel to understand current state:

```bash
# View all staged and unstaged changes
git status

# See exact modifications (staged and unstaged)
git diff
git diff --staged

# Review recent commits to understand message style
git log --oneline -10
```

**Why parallel**: These are independent readonly operations - no dependencies between them.

### Step 2: Determine Staging Strategy and Draft Message

Based on gathered information, first determine what to commit, then draft the message.

#### 2.1: Analyze Staging State

Count the files in each category from `git status`:

- **Staged files**: Files in "Changes to be committed" section
- **Modified files**: Files in "Changes not staged for commit" section (tracked files modified)
- **Untracked files**: Files in "Untracked files" section

#### 2.2: Apply Staging Decision Logic

##### Scenario A: Nothing to commit (staged=0, modified=0, untracked=0)

```text
Working tree is clean - nothing to commit.
```

Exit gracefully. No commit needed.

##### Scenario B: Files staged, nothing modified (staged>0, modified=0)

Proceed directly to commit. User has already staged exactly what they want.

##### Scenario C: Nothing staged, but changes exist (staged=0, modified>0 or untracked>0)

Ask user what to commit using AskUserQuestion:

```text
"I see {N} modified file(s) but nothing is staged yet. What would you like to commit?"

Options:
1. "Stage and commit all modified files" → `git add -u` (stage all tracked files)
2. "Let me stage specific files first" → Exit, let user stage manually, then re-run /commit
```

If user chooses option 1, proceed with all modified files.
If user chooses option 2, exit and inform them to run `git add <files>` then `/commit` again.

##### Scenario D: Mixed staging (staged>0, modified>0)

Ask user using AskUserQuestion:

```text
"I see {N} file(s) staged and {M} file(s) modified but not staged. What would you like to commit?"

Options:
1. "Commit only the staged files" → Proceed with staged files only
2. "Stage and commit everything" → `git add -u` then commit all
```

Respect user's choice.

#### 2.3: Draft Commit Message

After confirming what will be committed:

1. **Review all changes to be committed**
2. **Determine commit type** - feat, fix, docs, refactor, style, etc.
3. **Draft concise message** following Conventional Commits format
4. **Verify no secrets** - Check for `.env`, `credentials.json`, API keys, tokens
5. **Verify no absolute paths** - Ensure no `D:\repos\...`, `/home/user/...` in committed content
6. **Check SYSTEM-CHANGES.md** - If any system files touched, verify documented

**Message drafting checklist**:

- [ ] Correct type (feat/fix/docs/etc.)
- [ ] Optional scope if applicable
- [ ] Imperative mood description
- [ ] Body paragraph if needed (explain WHY)
- [ ] Attribution footer included
- [ ] Breaking change notation if applicable

### Step 3: Execute Commit (Sequential)

Run these commands in sequence (dependencies exist):

```bash
# Stage files if needed (based on Step 2 decision)
# - If user chose "stage all": git add -u
# - If files already staged: skip this step
# - If user is staging specific files: they should do this before running /commit

# Create commit with HEREDOC format (REQUIRED)
git commit -m "$(cat <<'EOF'
<type>[scope]: <description>

[optional body]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

# Verify commit succeeded
git status
```

**Why sequential**: Each operation depends on the previous completing successfully.

**CRITICAL**: ALWAYS use HEREDOC format with `$(cat <<'EOF' ... EOF)` to ensure proper formatting and avoid shell escaping issues.

**Staging commands reference**:

- `git add -u` - Stage all tracked modified files (doesn't include new untracked files)
- `git add -A` - Stage everything (tracked + untracked, modifications + deletions)
- `git add <file>` - Stage specific file(s)

### Step 4: Handle Pre-Commit Hook Failures

If commit fails due to pre-commit hooks (linters, formatters, etc.):

**Retry ONCE if hook modified files**:

```bash
# Check if files were modified by hook
git diff

# If modifications exist, check if safe to amend
git log -1 --format='%an %ae'  # Check authorship (must be you)
git status                      # Check not pushed (must show "ahead of")

# If BOTH checks pass, amend the commit:
git add .
git commit --amend --no-edit

# If EITHER check fails, create NEW commit instead:
git add .
git commit -m "$(cat <<'EOF'
chore: apply automated linting fixes

Pre-commit hooks applied automatic formatting changes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

**Amend safety protocol**:

- ✅ **Check authorship first**: `git log -1 --format='%an %ae'` - Only amend YOUR commits
- ✅ **Check not pushed**: `git status` must show "Your branch is ahead" (not pushed to remote)
- ✅ **Only if BOTH pass**: Then amend is safe
- ❌ **If EITHER fails**: Create new commit instead - NEVER amend others' commits or pushed commits

**When to skip retry**:

- Hook failed with errors (not just warnings)
- Hook did not modify files
- Safety checks failed (not your commit or already pushed)

## Pull Request Creation

When user requests pull request creation, follow this workflow.

### Step 1: Understand Branch Context (Parallel)

```bash
# View current branch status
git status

# See all changes since divergence from base branch
git diff main...HEAD    # Or other base branch
git log main...HEAD     # All commits that will be in PR

# Check remote tracking status
git branch -vv
```

### Step 2: Analyze ALL Commits

Review ALL commits that will be included in PR (NOT just the latest commit):

- Read all commit messages
- Understand full scope of changes
- Draft comprehensive PR summary covering entire branch

### Step 3: Create Pull Request (Sequential)

```bash
# Create new branch if needed
git checkout -b feature-branch-name

# Push to remote with tracking
git push -u origin feature-branch-name

# Create PR using HEREDOC for body
gh pr create --title "feat: Brief PR title" --body "$(cat <<'EOF'
## Summary
- Bullet point summary of changes
- Key features or fixes
- Breaking changes if any

## Test plan
- [ ] Manual testing steps
- [ ] Automated tests added/updated
- [ ] Documentation updated

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Return PR URL** when complete so user can view it.

**DO NOT push to remote** unless user explicitly requests PR creation or push.

## When to Commit

**Only create commits when:**

- ✅ User explicitly requests: "Create a commit", "Commit these changes", "Make a commit", etc.
- ✅ User confirms when asked for clarification
- ✅ Completing a task where commit was part of explicit requirements

**Do NOT commit when:**

- ❌ User asks to "save" or "update" without mentioning commit/git
- ❌ Completing edits without explicit commit request
- ❌ Uncertain about user intent
- ❌ Multiple logical changes that should be separate commits

**If unclear, ASK**: "Would you like me to create a commit with these changes?"

## System Changes Documentation

**CRITICAL REQUIREMENT**: Before committing, verify all system-level changes are documented.

### What Requires Documentation

Any changes made outside this repository:

- Configuration files (`~/.gitconfig`, `~/.ssh/config`, etc.)
- System-level keys or credentials (GPG keys, SSH keys)
- Cloud resources (GitHub Secrets, environment variables)
- Installed packages or tools
- Environment variable modifications

### Verification Process

Before executing commit:

1. **Ask yourself**: "Did I modify any files outside this repo?"
2. **If YES**: Check that `SYSTEM-CHANGES.md` has been updated
3. **If NO**: Proceed with commit

See `SYSTEM-CHANGES.md` format requirements in repository documentation.

## Examples

For concrete examples of common commit scenarios, see [references/examples.md](references/examples.md):

- Simple feature additions with proper scoping
- Bug fixes with detailed explanations
- Breaking changes with proper notation
- Documentation-only commits
- Multi-file refactoring examples

All examples follow Conventional Commits specification with required Claude Code attribution.

## Resources

This skill includes comprehensive reference documentation:

### references/

- See [references/conventional-commits-spec.md](references/conventional-commits-spec.md) for complete Conventional Commits specification
- See [references/safety-protocol.md](references/safety-protocol.md) for detailed safety rules and rationale
- See [references/workflow-steps.md](references/workflow-steps.md) for expanded workflow guidance with examples
- See [references/hook-handling.md](references/hook-handling.md) for complete pre-commit hook failure handling procedures
- See [references/examples.md](references/examples.md) for concrete commit examples following best practices
- See [references/troubleshooting.md](references/troubleshooting.md) for common issues and solutions
- See [references/testing.md](references/testing.md) for test scenarios and multi-model testing notes

## Troubleshooting

For solutions to common Git commit issues, see [references/troubleshooting.md](references/troubleshooting.md):

- GPG signing failures
- Pre-commit hook issues
- Commit type selection guidance
- Mixed staging state handling
- Amend safety check failures

All troubleshooting solutions follow safety protocols and never bypass hooks or GPG signing.

## Best Practices

- ✅ **Always use HEREDOC format** for commit messages - ensures proper formatting
- ✅ **Review changes before committing** - Run `git diff` and `git status` first
- ✅ **Commit logically related changes together** - Don't mix unrelated edits
- ✅ **Write descriptive commit messages** - Focus on WHY, not just WHAT
- ✅ **Use scopes consistently** - Pick scope names and stick with them across commits
- ✅ **Invoke git-commit skill** - Always use this skill before committing to ensure compliance
- ✅ **Verify system changes documented** - Check SYSTEM-CHANGES.md before committing
- ✅ **Follow safety protocols** - Never skip hooks or bypass GPG signing
- ❌ **Never commit secrets** - Add `.env`, `credentials.json` to `.gitignore`
- ❌ **Never commit absolute paths** - Use relative paths or placeholders
- ❌ **Never commit without explicit request** - Only commit when user asks

## Testing

For comprehensive test scenarios and multi-model testing guidance, see [references/testing.md](references/testing.md):

- Six detailed test scenarios covering common use cases
- Multi-model testing notes (Sonnet, Haiku, Opus)
- Expected behavior and success criteria for each scenario
- Evaluation criteria for skill quality assessment

Current testing status: Verified with Sonnet. Haiku and Opus testing pending.

## Version History

- v1.3.1 (2025-11-25): Audit improvements - standardize model references to use model families (Sonnet, Haiku, Opus) instead of specific versions, add Last Verified dates to examples.md, troubleshooting.md, and testing.md for consistency
- v1.3.0 (2025-11-17): Optimize SKILL.md for token efficiency - move Examples, Troubleshooting, and Testing to separate reference files; remove empty assets/ and scripts/ directories; improve progressive disclosure pattern
- v1.2.0 (2025-11-13): Add test scenarios and multi-model testing documentation, add execution verbs to description, remove unused template files from scripts/ and assets/ directories
- v1.1.0 (2025-11-13): Add intelligent staging decision logic - handles mixed staged/unstaged scenarios, asks user intent when ambiguous, detects "nothing to commit" gracefully
- v1.0.0 (2025-11-13): Initial release - comprehensive git commit skill with Conventional Commits specification, safety protocols, and complete workflow guidance

---

## Last Updated

**Date:** 2025-11-28
**Model:** claude-opus-4-5-20251101
