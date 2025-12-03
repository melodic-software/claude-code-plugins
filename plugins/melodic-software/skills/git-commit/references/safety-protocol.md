# Git Commit Safety Protocol

Comprehensive safety rules and rationale for safe git operations.

## Overview

This document provides detailed explanations of all safety rules (NEVER rules) that must be followed during git operations. These rules prevent destructive actions, maintain code integrity, and ensure team collaboration remains smooth.

## Table of Contents

- [Overview](#overview)
- [NEVER Rules (Non-Negotiable)](#never-rules-non-negotiable)
  - [1. NEVER Update Git Config](#1-never-update-git-config)
  - [2. NEVER Run Destructive Commands](#2-never-run-destructive-commands)
  - [3. NEVER Skip Hooks](#3-never-skip-hooks)
  - [4. NEVER Force Push to Main/Master](#4-never-force-push-to-mainmaster)
  - [5. NEVER Use `git commit --amend` (Except Specific Cases)](#5-never-use-git-commit---amend-except-specific-cases)
  - [6. NEVER Commit Without Explicit User Request](#6-never-commit-without-explicit-user-request)
  - [7. NEVER Commit Secret Files](#7-never-commit-secret-files)
  - [8. NEVER Use Interactive Git Commands](#8-never-use-interactive-git-commands)
- [Safety Verification Checklist](#safety-verification-checklist)
- [Consequences of Violating Safety Rules](#consequences-of-violating-safety-rules)
- [Recovery Procedures](#recovery-procedures)

## NEVER Rules (Non-Negotiable)

### 1. NEVER Update Git Config

**Rule**: Do not modify `.git/config`, `~/.gitconfig`, or run `git config` commands unless explicitly requested by user.

**Rationale**:

- Git configuration affects all repositories and operations
- Users have carefully configured their identity, signing keys, aliases
- Unintended changes can break workflows or expose wrong identity
- GPG signing configuration is security-sensitive

**Examples of forbidden operations**:

```bash
❌ git config user.name "Claude"
❌ git config user.email "claude@anthropic.com"
❌ git config --global commit.gpgsign false
❌ git config core.autocrlf true
```

**When config changes ARE allowed**:

- User explicitly requests: "Set my git email to..."
- User asks for configuration help: "How do I configure git signing?"
- User troubleshooting: "Can you check my git config?"

**Why this matters**: Changing git identity could result in commits appearing under wrong authorship, breaking organizational policies or security requirements.

### 2. NEVER Run Destructive Commands

**Rule**: Avoid destructive git operations unless user explicitly requests them with full understanding.

**Prohibited commands**:

```bash
❌ git push --force
❌ git push -f
❌ git reset --hard
❌ git clean -fd
❌ git rebase (when rewriting published history)
❌ git filter-branch
❌ git reflog expire
```

**Rationale**:

- These commands permanently delete data or rewrite history
- Can affect other team members if used on shared branches
- May cause data loss or broken repository state
- Recovery often requires deep git knowledge

**When destructive commands ARE allowed**:

- User explicitly requests: "Force push this branch"
- User understands consequences: Confirmed after warning
- User is working on personal branch: Not affecting team

**Warning protocol**:

```text
⚠️  WARNING: git push --force will overwrite remote history.
This may affect other developers working on this branch.
Are you sure you want to proceed? (yes/no)
```

### 3. NEVER Skip Hooks

**Rule**: Never use `--no-verify` or `--no-gpg-sign` flags unless user explicitly requests.

**Prohibited flags**:

```bash
❌ git commit --no-verify
❌ git commit --no-gpg-sign
❌ git commit -n  (short for --no-verify)
❌ git push --no-verify
```

**Rationale**:

- Pre-commit hooks enforce code quality (linting, formatting, tests)
- GPG signing provides commit authentication and non-repudiation
- Skipping hooks bypasses team quality standards
- Creates inconsistent codebase quality

**Why hooks exist**:

- **Pre-commit**: Lint code, format, run quick tests
- **Commit-msg**: Validate commit message format
- **Pre-push**: Run test suite, prevent pushing broken code
- **GPG signing**: Verify commit author identity cryptographically

**When skipping IS allowed**:

- User explicitly requests: "Commit with --no-verify"
- Emergency situation: User confirms understanding of risks
- Hook is broken: User working to fix the hook itself

**Better alternatives**:

- Fix the underlying issue (lint errors, failing tests)
- Temporarily disable specific hook if truly problematic
- Fix GPG setup instead of bypassing signing

### 4. NEVER Force Push to Main/Master

**Rule**: Never `git push --force` to main/master branches. Warn user if requested.

**Why this is critical**:

- Main/master are protected branches with entire team working from them
- Force push rewrites history, breaking everyone's local clones
- Causes conflicts for all developers when they pull
- May violate branch protection rules on hosting platform

**Warning message**:

```text
⚠️  DANGER: Force pushing to main/master is extremely dangerous!

This will:
- Overwrite remote history
- Break all team members' local repositories
- Potentially lose commits from other developers
- May violate branch protection policies

Recommended alternatives:
- Create a revert commit instead: git revert <commit>
- Create a new branch: git checkout -b fix-branch
- Merge forward instead of rewriting history

Do you still want to force push to main? (yes/no)
```

**Alternatives to force push**:

```bash
✅ git revert <commit-hash>     # Undo commit with new commit
✅ git checkout -b fix-branch   # Work on feature branch
✅ git merge --no-ff main       # Merge forward, don't rewrite
```

### 5. NEVER Use `git commit --amend` (Except Specific Cases)

**Rule**: Avoid `--amend` except when user explicitly requests OR pre-commit hook modified files (with safety checks).

**Why amending is risky**:

- Rewrites commit history (changes commit SHA)
- Breaks anyone who pulled the original commit
- Can overwrite others' work if amending wrong commit
- Causes confusion in shared branches

**Two permitted use cases**:

#### Case 1: User Explicitly Requests

```bash
# User says: "Amend the last commit to include this file"
✅ git add forgotten-file.txt
✅ git commit --amend --no-edit
```

#### Case 2: Pre-Commit Hook Modified Files

**ONLY if both safety checks pass**:

```bash
# Safety Check 1: Verify authorship (must be your commit)
git log -1 --format='%an %ae'
# Expected: Your Name <your@email.com>

# Safety Check 2: Verify not pushed (must be local only)
git status
# Expected: "Your branch is ahead of 'origin/main' by 1 commit"

# If BOTH checks pass:
✅ git add .
✅ git commit --amend --no-edit

# If EITHER check fails:
✅ git add .
✅ git commit -m "chore: apply automated linting fixes"
```

**Why these safety checks**:

- **Authorship check**: NEVER amend someone else's commit - creates attribution confusion
- **Push check**: NEVER amend pushed commits - breaks others' repositories

**Alternative to amending**:

```bash
✅ git commit -m "chore: address review feedback"
✅ git commit -m "fix: typo in previous commit"
```

Creating a new commit is always safer than amending.

### 6. NEVER Commit Without Explicit User Request

**Rule**: Only create commits when user explicitly asks. If unclear, ask first.

**This is VERY IMPORTANT** - emphasized in system instructions.

**Explicit requests (commit allowed)**:

- ✅ "Create a commit with these changes"
- ✅ "Commit this file"
- ✅ "Make a commit"
- ✅ "Commit and push"

**Ambiguous requests (ask first)**:

- ❓ "Save these changes" - Could mean file save or git commit
- ❓ "Finish this task" - May or may not include committing
- ❓ "Update the code" - Editing vs committing unclear

**Clear non-requests (don't commit)**:

- ❌ "Edit this file" - Just edit, don't commit
- ❌ "Update the documentation" - Make changes, don't commit
- ❌ "Fix this bug" - Fix code, wait for commit request

**When to ask**:

```text
I've completed the requested changes. Would you like me to create a git commit?
```

**Rationale**:

- Users may want to review changes before committing
- Users may want to combine multiple edits into one commit
- Users may be following specific git workflow (feature branches, etc.)
- Committing prematurely fragments history unnecessarily

### 7. NEVER Commit Secret Files

**Rule**: Do not commit files likely to contain secrets. Warn user if they request it.

**Common secret files**:

```text
❌ .env
❌ .env.local
❌ .env.production
❌ credentials.json
❌ secrets.yaml
❌ config/secrets.yml
❌ *.pem (private keys)
❌ *.key (private keys)
❌ id_rsa (SSH private key)
```

**Warning message**:

```text
⚠️  WARNING: This file appears to contain secrets or credentials.

File: .env
Risk: Committing secrets to git exposes them in repository history permanently.

Recommendation:
- Add this file to .gitignore
- Use environment variables or secret management tools
- Use git-secrets or similar tools to prevent accidental commits

Do you still want to commit this file? (yes/no)
```

**Why this matters**:

- Secrets in git history are effectively public (even if repo is private)
- Removing secrets from history is difficult (requires rewriting entire history)
- Compliance violations (PCI-DSS, SOC 2, etc.)
- Security breaches if repository is exposed

**Best practices**:

```bash
# Add secret files to .gitignore
echo ".env" >> .gitignore
echo "credentials.json" >> .gitignore
git add .gitignore
git commit -m "chore: add secret files to gitignore"
```

### 8. NEVER Use Interactive Git Commands

**Rule**: Avoid git commands with `-i` flag (interactive mode).

**Prohibited commands**:

```bash
❌ git rebase -i
❌ git add -i
❌ git add --interactive
❌ git add -p  (interactive patch mode)
```

**Rationale**:

- Interactive commands require user input via terminal prompts
- Claude Code operates in non-interactive environments
- Commands will hang or fail without user interaction
- Alternative approaches exist for same functionality

**Alternatives**:

```bash
# Instead of: git add -i
✅ git add <specific-files>

# Instead of: git rebase -i
✅ git rebase <branch> (non-interactive)
✅ git reset HEAD~1 (undo last commit)

# Instead of: git add -p
✅ git add <specific-file>
✅ git diff (review first, then add)
```

## Safety Verification Checklist

Before executing ANY commit, verify:

### 1. Check for Secrets

Scan staged files for:

- Environment files (`.env*`)
- Credential files (`credentials.json`, `secrets.yaml`)
- Private keys (`*.pem`, `*.key`, `id_rsa`)
- API keys or tokens in code
- Passwords or connection strings

**Commands to check**:

```bash
# List staged files
git diff --staged --name-only

# Search staged content for common secret patterns
git diff --staged | grep -iE "(password|api[_-]?key|secret|token|private[_-]?key)"
```

### 2. Check for Absolute Paths

Ensure no machine-specific paths in committed content:

**Forbidden patterns**:

```text
❌ D:\repos\gh\melodic\onboarding\...
❌ C:\Users\JohnDoe\...
❌ /home/username/projects/...
❌ /Users/jane/repos/...
```

**Allowed patterns**:

```text
✅ .gitignore (relative path)
✅ <project-root>/docs/file.md (placeholder)
✅ ~/config (user home placeholder)
✅ docs/windows-onboarding.md (relative)
```

**Commands to check**:

```bash
# Search for Windows absolute paths
git diff --staged | grep -E "[A-Z]:\\\\"

# Search for Unix absolute paths (home directories)
git diff --staged | grep -E "/home/[a-z]+"
git diff --staged | grep -E "/Users/[a-z]+"
```

### 3. Verify SYSTEM-CHANGES.md Updated

If ANY system files were modified (outside repository):

**System file categories**:

- Config files: `~/.gitconfig`, `~/.ssh/config`, `~/.gnupg/gpg.conf`
- Keys/credentials: GPG keys, SSH keys
- Cloud resources: GitHub Secrets, environment variables
- Packages: Installed tools or libraries
- Environment: Shell configs (`.bashrc`, `.zshrc`)

**Verification process**:

```bash
# Check if SYSTEM-CHANGES.md was modified
git status | grep "SYSTEM-CHANGES.md"

# If system files touched but SYSTEM-CHANGES.md not modified:
❌ Do not commit - ask user to document changes first
```

**Why this matters**:

- System changes are invisible to repository
- Documentation creates audit trail
- Team members need to replicate system setup
- Troubleshooting requires knowing what changed

### 4. Confirm User Intent

If there's ANY uncertainty about whether to commit:

**Ask explicitly**:

```text
I've completed the requested changes to [files]. Would you like me to create a git commit?
```

**Don't assume**:

- User editing doesn't imply committing
- Completing task doesn't imply committing
- "Save" doesn't necessarily mean "commit"

**Wait for clear confirmation**.

## Consequences of Violating Safety Rules

### Broken Team Collaboration

- Force pushes break everyone's local repositories
- Amending pushed commits causes merge conflicts
- Skipping hooks creates inconsistent code quality

### Security Risks

- Committed secrets exposed in history
- Bypassed GPG signing removes authentication
- Config changes may expose sensitive information

### Data Loss

- Hard resets permanently delete work
- Force pushes overwrite others' commits
- Interactive rebases gone wrong require recovery

### Compliance Violations

- Missing GPG signatures violate security policies
- Committed secrets violate PCI-DSS, SOC 2, etc.
- Unverified authorship violates audit requirements

## Recovery Procedures

If safety rules are violated, recovery steps vary:

### Committed Secrets

```bash
# Remove from history (rewrites all commits - coordinate with team)
git filter-branch --tree-filter 'rm -f .env' HEAD
git push --force-with-lease
```

**Better**: Rotate the exposed secrets immediately.

### Force Pushed to Main

```bash
# If others haven't pulled yet, restore from backup
git reset --hard <previous-commit-sha>
git push --force-with-lease

# If others have pulled, coordinate recovery with team
```

### Skipped Pre-Commit Hooks

```bash
# Create follow-up commit with fixes
npm run lint -- --fix
git add .
git commit -m "chore: apply linting fixes from pre-commit hook"
```

---

**Last Verified:** 2025-11-25
**Related Skills**: git:gpg-signing, git:config
