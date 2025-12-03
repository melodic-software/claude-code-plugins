# Git Commit Workflow Steps

Expanded guidance for the complete 4-step commit workflow with detailed examples and best practices.

## Table of Contents

- [Overview](#overview)
- [Step 1: Gather Information (Parallel)](#step-1-gather-information-parallel)
- [Step 2: Analyze and Draft Message](#step-2-analyze-and-draft-message)
- [Step 3: Execute Commit (Sequential)](#step-3-execute-commit-sequential)
- [Step 4: Handle Pre-Commit Hook Failures](#step-4-handle-pre-commit-hook-failures)
- [Complete Workflow Example](#complete-workflow-example)

## Overview

Every git commit should follow this structured 4-step workflow:

1. **Gather Information** (parallel readonly operations)
2. **Analyze and Draft** (review changes, draft message)
3. **Execute Commit** (sequential operations with dependencies)
4. **Handle Hook Failures** (retry logic for pre-commit hooks)

This workflow ensures safety, consistency, and proper documentation of all changes.

## Step 1: Gather Information (Parallel)

**Goal**: Understand current repository state before making any changes.

**Why parallel**: These are independent readonly operations with no dependencies.

### Commands to Run

```bash
# View all staged and unstaged changes
git status

# See exact modifications (staged changes)
git diff --staged

# See exact modifications (unstaged changes)
git diff

# Review recent commits to understand message style
git log --oneline -10

# See recent commit details
git log -3 --format=fuller
```

### What to Look For

#### In `git status` output

**Staged files** (green, "Changes to be committed"):

- These WILL be included in the commit
- Verify all intended files are staged
- Check for accidental staging (lockfiles, build artifacts)

**Unstaged files** (red, "Changes not staged for commit"):

- These will NOT be included unless explicitly added
- Decide if any should be staged

**Untracked files** (red, "Untracked files"):

- New files not yet added to git
- Check if any should be included
- Verify no secrets or temp files

**Example output**:

```text
On branch main
Your branch is up to date with 'origin/main'.

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
        modified:   src/auth/login.ts
        new file:   src/auth/token-refresh.ts

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   README.md

Untracked files:
  (use "git add <file>..." to include in what will be committed)
        src/auth/session.ts
```

#### In `git diff --staged` output

**Verify changes make sense**:

- No accidentally included debug code
- No commented-out code left behind
- No absolute paths introduced
- No sensitive information
- Logical coherence (related changes)

**Example review**:

```diff
+ export const refreshToken = async (token: string) => {
+   const response = await api.post('/auth/refresh', { token });
+   return response.data.accessToken;
+ };
```

**Questions to ask**:

- ✅ Is this the intended change?
- ✅ Does this introduce any bugs?
- ✅ Are there any hardcoded values that should be configurable?
- ✅ Does this match the commit type I'm planning (feat, fix, etc.)?

#### In `git log` output

**Understand commit message patterns**:

- How does team write commit messages?
- What types are commonly used? (feat, fix, docs, chore, etc.)
- How detailed are message bodies?
- What scope naming conventions are used?

**Example log output**:

```text
a3d9f2e feat(api): add user profile endpoint
c8e1b7a fix(auth): resolve token expiration issue
5f2a9c3 docs: update API documentation
e7d3a1b chore(deps): upgrade typescript to 5.0
```

**What this tells you**:

- Team uses conventional commits
- Scopes are feature-based (api, auth)
- Mix of types (feat, fix, docs, chore)
- Concise descriptions (~50 chars)

### Execution Pattern

**Run these commands in parallel** (use multiple Bash tool calls in single message):

```markdown
# In a single message, make three Bash tool calls:
1. git status
2. git diff --staged
3. git log --oneline -10
```

**Why parallel matters**:

- Faster execution (no waiting between commands)
- No dependencies between these operations
- All are readonly (safe to run concurrently)

## Step 2: Analyze and Draft Message

**Goal**: Determine commit type, draft message, and verify safety.

### Determine Commit Type

Use this decision tree:

```text
Did you add new functionality? → feat
Did you fix a bug? → fix
Did you only change documentation? → docs
Did you only reformat code (no logic change)? → style
Did you restructure without changing behavior? → refactor
Did you improve performance? → perf
Did you add/update tests? → test
Did you update dependencies or configs? → chore
Did you change CI/CD configs? → ci
Did you change build system? → build
```

**Examples**:

| Change | Type |
| ------ | ---- |
| Added user authentication feature | `feat` |
| Fixed memory leak in parser | `fix` |
| Updated README installation steps | `docs` |
| Reformatted code with Prettier | `style` |
| Extracted function to utils | `refactor` |
| Optimized database queries | `perf` |
| Added unit tests for auth module | `test` |
| Upgraded dependencies to latest | `chore` |
| Updated GitHub Actions workflow | `ci` |
| Modified webpack configuration | `build` |

### Determine Scope (Optional)

**Scope provides context about what part of codebase changed**.

**Good scope examples**:

- `feat(api): add user endpoint` - API layer
- `fix(database): resolve connection timeout` - Database layer
- `docs(readme): update installation` - README file
- `refactor(auth): simplify token logic` - Auth module

**When to use scope**:

- ✅ Monorepo with multiple packages: `feat(admin-ui):`
- ✅ Clear feature boundaries: `fix(payments):`
- ✅ Team convention uses scopes consistently
- ❌ Small single-purpose repository (scope may be redundant)
- ❌ Change spans multiple areas (scope becomes unclear)

### Draft Description

**Rules**:

1. Use imperative mood: "add feature" not "added feature"
2. Lowercase first letter: "add user login" not "Add user login"
3. No period at end: "fix bug" not "fix bug."
4. Target ~50 characters, max 72
5. Focus on WHAT changed (WHY goes in body)

**Good descriptions**:

- ✅ `add JWT token refresh endpoint`
- ✅ `fix memory leak in data processor`
- ✅ `update installation instructions`
- ✅ `refactor authentication logic for clarity`

**Bad descriptions**:

- ❌ `Added feature` (past tense, too vague)
- ❌ `Fix` (too brief, no context)
- ❌ `Update the README file with new installation instructions and fix typos` (too long)
- ❌ `Fixes issue #123` (no description of actual change)

### Draft Body (Optional)

**When to include body**:

- Change is non-obvious (needs explanation)
- Need to explain WHY, not just WHAT
- Breaking change requiring migration steps
- Complex refactoring with rationale

**Body guidelines**:

- Separated from description by blank line
- Wrap at 72 characters per line
- Can include multiple paragraphs
- Explain motivation and contrast with previous behavior

**Example with body**:

```text
feat(auth): add JWT token refresh mechanism

Implements automatic token refresh to improve user experience
and reduce unnecessary re-authentication. Previous behavior
required users to log in again after token expiration.

The refresh token is stored securely in httpOnly cookie and
automatically used when access token expires.
```

### Safety Verification Checklist

Before proceeding to Step 3, verify:

#### ✅ Check for Secrets

**Scan staged files**:

```bash
# List staged files
git diff --staged --name-only

# Check for secret filenames
git diff --staged --name-only | grep -iE "(\.env|credentials|secrets|\.pem|\.key)"

# Check for secret patterns in content
git diff --staged | grep -iE "(password|api[_-]?key|secret|token|private[_-]?key|bearer)"
```

**Common secret patterns**:

- `.env` files (environment variables)
- `credentials.json` (GCP, service accounts)
- `*.pem`, `*.key` (private keys)
- `id_rsa` (SSH private keys)
- Hardcoded passwords or tokens in code

**If secrets found**:

1. Stop immediately - do not commit
2. Remove secrets from staged files
3. Add secret files to `.gitignore`
4. Use environment variables or secret management tools

#### ✅ Check for Absolute Paths

**Scan staged content**:

```bash
# Check for Windows absolute paths
git diff --staged | grep -E "[A-Z]:\\\\"

# Check for Unix absolute paths
git diff --staged | grep -E "/(home|Users)/[a-z0-9]+"
```

**Forbidden patterns**:

- `D:\repos\gh\melodic\onboarding\...` (Windows)
- `/home/username/projects/...` (Linux)
- `/Users/jane/repos/...` (macOS)
- `C:\Users\JohnDoe\...` (Windows user)

**Allowed patterns**:

- `docs/file.md` (relative)
- `<project-root>/docs/file.md` (placeholder)
- `~/config` (user home placeholder)
- `C:\Users\[YourUsername]\` (generic template)

#### ✅ Verify SYSTEM-CHANGES.md

**Question**: Did I modify any files outside this repository?

**System file categories**:

- Configuration files: `~/.gitconfig`, `~/.ssh/config`, `~/.bashrc`
- Keys/credentials: GPG keys, SSH keys
- Cloud resources: GitHub Secrets, environment variables
- Packages: System-installed tools or libraries
- Environment: PATH modifications, shell aliases

**If YES**:

```bash
# Verify SYSTEM-CHANGES.md was updated
git status | grep "SYSTEM-CHANGES.md"

# If not staged:
❌ Do not proceed with commit
❌ Document changes in SYSTEM-CHANGES.md first
❌ Then stage and commit together
```

**If NO**:

✅ Proceed with commit

#### ✅ Confirm User Intent

**If there's ANY uncertainty about whether to commit**:

```text
I've reviewed the changes to [list files]. The commit would be:

Type: feat
Scope: auth
Description: add JWT token refresh mechanism

Would you like me to create this commit?
```

**When to ask**:

- User said "update" or "save" without mentioning "commit"
- Completing task where commit wasn't explicitly requested
- Multiple logical changes that might be split into separate commits

**Wait for explicit confirmation**.

## Step 3: Execute Commit (Sequential)

**Goal**: Stage files and create commit with proper message format.

**Why sequential**: Each operation depends on the previous succeeding.

### Stage Files

```bash
# Stage specific files
git add src/auth/login.ts src/auth/token-refresh.ts

# Or stage all modified/new files
git add .

# Or stage by pattern
git add src/auth/*.ts
```

**Be intentional about what you stage**:

- Don't blindly `git add .` without reviewing
- Exclude build artifacts, lockfiles, temp files
- Consider separate commits for logically distinct changes

### Create Commit with HEREDOC

**CRITICAL**: ALWAYS use HEREDOC format for multi-line messages.

**Basic format**:

```bash
git commit -m "$(cat <<'EOF'
<type>[scope]: <description>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

**With body**:

```bash
git commit -m "$(cat <<'EOF'
<type>[scope]: <description>

[Multi-line body explaining WHY this change was made
and providing additional context.]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

**Why HEREDOC**:

- Preserves exact formatting and line breaks
- Avoids shell escaping issues with quotes
- Ensures attribution footer is formatted correctly
- Prevents accidental truncation of multi-line messages

**Common mistake (DON'T DO THIS)**:

```bash
❌ git commit -m "feat: add feature\n\nBody text"
   # Shell escaping breaks formatting
   # Attribution footer would be malformed

❌ git commit -m "feat: add feature" -m "Body text" -m "Attribution"
   # Multiple -m flags create paragraphs unpredictably
   # Hard to ensure correct formatting

✅ git commit -m "$(cat <<'EOF'
feat: add feature

Body text

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
   # CORRECT: HEREDOC ensures proper formatting
```

### Verify Commit Succeeded

```bash
# Check that commit was created
git status

# View the commit just created
git log -1

# View the commit with full details
git show HEAD
```

**Expected output from `git status`**:

```text
On branch main
Your branch is ahead of 'origin/main' by 1 commit.
  (use "git push" to publish your local commits)

nothing to commit, working tree clean
```

**What to verify**:

- ✅ "nothing to commit" (all changes committed)
- ✅ "Your branch is ahead" (commit created)
- ✅ Working tree is clean (no uncommitted changes)

**If commit failed**:

- Read error message carefully
- Check for pre-commit hook failures (see Step 4)
- Check for GPG signing issues (see Troubleshooting)
- Verify staged files: `git status`

## Step 4: Handle Pre-Commit Hook Failures

**Goal**: Handle automated tooling failures gracefully.

This step is only needed if commit fails due to pre-commit hooks.

**See [hook-handling.md](hook-handling.md) for complete guidance.**

### Quick Reference

**If commit fails with hook error**:

1. Read hook output to understand issue
2. Fix underlying problems (lint errors, test failures)
3. Stage fixed files: `git add .`
4. Retry commit

**If hook modified files automatically**:

1. Check if safe to amend (see hook-handling.md)
2. If safe: `git commit --amend --no-edit`
3. If not safe: Create new commit

**NEVER**:

- ❌ Use `--no-verify` to skip hooks
- ❌ Amend without safety checks
- ❌ Ignore hook errors

## Complete Workflow Example

### Scenario: Adding JWT Token Refresh Feature

#### Example Step 1: Gather Information (Parallel)

```bash
# Run in parallel
git status
git diff --staged
git log --oneline -10
```

**Output analysis**:

- Staged: `src/auth/token-refresh.ts` (new file), `src/auth/login.ts` (modified)
- Team uses conventional commits with scopes
- Recent commits show `feat(auth):` pattern

#### Example Step 2: Analyze and Draft

**Type**: `feat` (new functionality)
**Scope**: `auth` (matches team convention)
**Description**: `add JWT token refresh mechanism`
**Body**: Explain why this improves UX

**Safety checks**:

- ✅ No secrets (no `.env` files, no hardcoded tokens)
- ✅ No absolute paths (all relative imports)
- ✅ No system changes (only repository files modified)
- ✅ User explicitly requested commit

#### Example Step 3: Execute Commit (Sequential)

```bash
# Already staged, so skip git add

# Create commit with HEREDOC
git commit -m "$(cat <<'EOF'
feat(auth): add JWT token refresh mechanism

Implements automatic token refresh to improve user experience
and reduce unnecessary re-authentication. Previous behavior
required users to log in again after token expiration.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

# Verify
git status
# Output: "nothing to commit, working tree clean"
# Output: "Your branch is ahead of 'origin/main' by 1 commit"
```

#### Example Step 4: Handle Hook Failures

Commit succeeded - no hook failures. Step 4 skipped.

**Result**: Successful commit following all protocols.

---

**Last Verified:** 2025-11-25
**Related**: safety-protocol.md, hook-handling.md, conventional-commits-spec.md
