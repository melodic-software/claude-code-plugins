# GitHub Actions Configuration Guide

**Optional/Advanced:** This guide is for setting up automated markdown linting in CI/CD. **You do NOT need this to use markdownlint** - CLI linting (npx or npm scripts) works without GitHub Actions.

**Benefits of GitHub Actions integration:**

- Automatically check PRs for linting errors
- Enforce quality standards before merge
- Prevent bad markdown from entering main branch
- Team-wide consistency without manual checks

Detailed documentation for setting up the markdown linting GitHub Actions workflow.

## Table of Contents

- [Initial Setup](#initial-setup)
- [Workflow Overview](#workflow-overview)
- [Workflow Configuration](#workflow-configuration)
- [How It Works](#how-it-works)
- [Viewing Results](#viewing-results)
- [Advanced Configuration](#advanced-configuration)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Integration with Branch Protection](#integration-with-branch-protection)
- [Resources](#resources)

## Initial Setup

Before configuring the workflow, ensure you have:

1. **A GitHub repository** with markdown files
2. **`.markdownlint-cli2.jsonc` configuration file** in project root (see [Installation Setup Guide](installation-setup.md))
3. **GitHub Actions enabled** on your repository (enabled by default for most repos)

### Creating the Workflow File

**Step 1: Create workflow directory (if it doesn't exist):**

```bash
mkdir -p .github/workflows
```

**Step 2: Create the workflow file `.github/workflows/markdown-lint.yml`:**

Use the configuration shown in the "Workflow Configuration" section below.

**Step 3: Commit and push the workflow file:**

```bash
git add .github/workflows/markdown-lint.yml
git commit -m "Add markdown linting GitHub Actions workflow"
git push
```

**Step 4: Verify workflow:**

- Navigate to your repository's "Actions" tab on GitHub
- You should see the "Markdown Lint" workflow listed
- Create a test PR or push to see it run

## Workflow Overview

**File:** `.github/workflows/markdown-lint.yml`

**Purpose:** Automatically lint all markdown files on pull requests and pushes to main branch, ensuring documentation quality standards are maintained.

## Workflow Configuration

### Full Workflow File

```yaml
name: Markdown Lint

on:
  pull_request:
    paths:
      - '**.md'
  push:
    branches:
      - main
    paths:
      - '**.md'

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run markdownlint-cli2
        uses: DavidAnson/markdownlint-cli2-action@v21
        with:
          globs: '**/*.md'
```

### Breakdown

#### Trigger Configuration

```yaml
on:
  pull_request:
    paths:
      - '**.md'
  push:
    branches:
      - main
    paths:
      - '**.md'
```

**Triggers:**

1. **Pull Requests:**
   - Any PR that modifies `.md` files
   - Includes new files, edits, and deletions
   - Filters by file extension using `paths` filter

2. **Push to Main:**
   - Direct pushes to `main` branch
   - Only when `.md` files are modified
   - Ensures main branch always passes linting

**Why this configuration:**

- **Efficient:** Only runs when markdown files are modified (not on every commit)
- **Comprehensive:** Catches issues in PRs before merge AND on main branch
- **Fast feedback:** PR checks fail immediately if linting errors exist

#### Job Configuration

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
```

**Runner:** Ubuntu latest (Linux environment)

**Why Ubuntu:**

- Fast startup time
- Consistent environment
- Supports all necessary tools
- Cost-effective (GitHub-hosted runner)

#### Steps

##### Step 1: Checkout Code

```yaml
- name: Checkout code
  uses: actions/checkout@v4
```

**What it does:**

- Checks out project code to the runner
- Uses official GitHub checkout action (v4)
- Downloads all files needed for linting

##### Step 2: Run markdownlint-cli2

```yaml
- name: Run markdownlint-cli2
  uses: DavidAnson/markdownlint-cli2-action@v21
  with:
    globs: '**/*.md'
```

**What it does:**

- Runs markdownlint-cli2 against all markdown files
- Uses official action by David Anson (v21)
- Reads `.markdownlint-cli2.jsonc` configuration automatically
- Reports violations as errors

**Configuration:**

- `globs: '**/*.md'` - Recursively checks all `.md` files
- Automatically excludes `node_modules` (action default)
- Uses project's `.markdownlint-cli2.jsonc` configuration (if present)

## How It Works

### Execution Flow

1. **Event occurs** (PR created/updated, or push to main)
2. **Workflow triggers** (if markdown files modified)
3. **Runner provisions** (Ubuntu VM spins up)
4. **Code checkout** (project code downloaded to runner)
5. **Linting executes** (markdownlint-cli2 runs against all .md files)
6. **Results reported** (pass/fail status updated on PR or commit)

### Success Criteria

**Workflow Passes:**

- No markdown linting errors found
- All files comply with `.markdownlint-cli2.jsonc` rules
- PR check shows green checkmark
- Merge is allowed (if no other checks fail)

**Workflow Fails:**

- One or more linting errors found
- PR check shows red X
- Details available in workflow logs
- Merge is blocked (if branch protection enabled)

### Configuration Source

The action automatically reads `.markdownlint-cli2.jsonc` from the project root as the single source of truth:

```jsonc
{
  "gitignore": true,
  "ignores": ["vendor/**/*.md"],
  "config": {
    "default": true,
    "MD013": false
  }
}
```

**Important:** The action uses the **exact same configuration** as:

- Local CLI commands (npx or npm scripts)
- VS Code markdownlint extension

This ensures **no surprises** - if linting passes locally, it will pass in CI.

## Viewing Results

### Successful Workflow

**On Pull Request:**

1. PR shows "All checks have passed"
2. Green checkmark next to "Markdown Lint" check
3. Safe to merge (assuming other checks pass)

**On Commit:**

1. Commit status shows green checkmark
2. Workflow run listed in Actions tab
3. No action needed

### Failed Workflow

**On Pull Request:**

1. PR shows "Some checks failed"
2. Red X next to "Markdown Lint" check
3. Click "Details" to see errors

**Viewing Error Details:**

1. Click **Details** link on failed check
2. Navigate to **"Run markdownlint-cli2"** step
3. Expand step to see full output
4. Errors listed with file paths and line numbers

**Example error output:**

```text
docs/windows-onboarding.md:45:1 MD022/blanks-around-headings Headings should be surrounded by blank lines [Context: "## Installation"]
docs/version-control/git-setup-windows.md:12:81 MD009/no-trailing-spaces Trailing spaces [Expected: 0, Actual: 2]
Error: Process completed with exit code 1.
```

### Fixing Failures

**Step-by-step process:**

1. **Identify errors:**
   - Review workflow output
   - Note file paths and line numbers
   - Note rule violations

2. **Fix locally:**
   - Checkout the PR branch
   - Run linting to reproduce errors:
     - With npx: `npx markdownlint-cli2 "**/*.md"`
     - With npm scripts: `npm run lint:md`
   - Auto-fix what's possible:
     - With npx: `npx markdownlint-cli2 "**/*.md" --fix`
     - With npm scripts: `npm run lint:md:fix`
   - Manually fix remaining errors

3. **Verify fix:**
   - Run linting again to ensure all errors are resolved
   - Ensure exit code 0 (no errors)
   - Commit fixes

4. **Push changes:**
   - Push to PR branch
   - Workflow re-runs automatically
   - Check results on PR

## Advanced Configuration

### Customizing Globs

To lint specific directories only:

```yaml
with:
  globs: 'docs/**/*.md'  # Only lint docs/ directory
```

To exclude specific files:

```yaml
with:
  globs: |
    **/*.md
    !**/CHANGELOG.md  # Exclude changelog files
```

**Note:** Default configuration lints all `.md` files, which is appropriate for most projects.

### Adding Auto-Fix (Optional)

**Not currently implemented** - would require additional complexity:

```yaml
- name: Run markdownlint-cli2 with auto-fix
  uses: DavidAnson/markdownlint-cli2-action@v21
  with:
    globs: '**/*.md'
    fix: true

- name: Commit fixes
  if: failure()
  run: |
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add -A
    git commit -m "Auto-fix markdown linting errors"
    git push
```

**Considerations:**

- Automated commits may be unwanted
- Could create noise in git history
- Better to fix locally before pushing

### Running on Different Branches

To lint all branches (not recommended):

```yaml
on:
  pull_request:
  push:
```

**Why not recommended:**

- Wastes CI minutes on branches without markdown changes
- Slower feedback on PRs
- Better to filter by `paths: ['**.md']`

### Different Runner OS

To test on multiple operating systems:

```yaml
jobs:
  lint:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
```

**Why not needed:**

- Markdownlint is OS-agnostic
- Configuration is portable
- Ubuntu is sufficient and fastest

## Troubleshooting

### Workflow Not Triggering

**Possible causes:**

1. Markdown files not modified
2. Workflow file syntax error
3. Branch protection not configured

**Solutions:**

1. **Verify trigger:**
   - Ensure `.md` files were modified in commit
   - Check `paths` filter in workflow file
   - Trigger only runs when markdown files change

2. **Validate workflow syntax:**
   - Open `.github/workflows/markdown-lint.yml`
   - Look for YAML syntax errors
   - Use [YAML validator](https://www.yamllint.com) if needed

3. **Check Actions tab:**
   - Navigate to repository Actions tab
   - Look for workflow runs
   - Check if workflow is disabled

### Workflow Fails But Local Linting Passes

**Possible causes:**

1. Configuration file not committed
2. Different file set being checked
3. Cache issue

**Solutions:**

1. **Verify configuration committed:**
   - Check `.markdownlint-cli2.jsonc` is in project root
   - Ensure not listed in `.gitignore`
   - Push configuration to remote

2. **Check file coverage:**
   - Local linting checks `"**/*.md"` (with npx or npm scripts)
   - CI: Action checks `'**/*.md'`
   - Should be identical

3. **Clear cache and re-run:**
   - Re-run workflow from Actions tab
   - Check for transient errors

### Workflow Passes But Should Fail

**Possible causes:**

1. Wrong glob pattern (not checking all files)
2. Configuration disables all rules
3. Action version issue

**Solutions:**

1. **Verify globs:**
   - Check `globs: '**/*.md'` in workflow
   - Ensure covers all markdown files
   - Test locally with same glob

2. **Check configuration:**
   - Open `.markdownlint-cli2.jsonc`
   - Ensure rules are enabled (not all `false`)
   - Should have `"default": true` in `config` property

3. **Update action version:**
   - Check for newer versions: [github.com/DavidAnson/markdownlint-cli2-action](https://github.com/DavidAnson/markdownlint-cli2-action)
   - Update to latest version (currently v21)

### Excessive CI Minutes Usage

**Possible causes:**

1. Running on all commits (not filtered by paths)
2. Running on too many branches
3. Large repository

**Solutions:**

1. **Verify path filtering:**
   - Ensure `paths: ['**.md']` is present
   - Workflow only runs when markdown files change

2. **Limit branches:**
   - Recommended config limits to PRs and main branch
   - Don't remove branch filtering

3. **Monitor usage:**
   - Check Settings - Actions - Usage in your repository
   - Markdown linting is very fast (typically <30 seconds)

## Best Practices

1. **Always run local linting first** - Catch errors before pushing
2. **Don't bypass CI checks** - If workflow fails, fix the issues
3. **Don't disable the workflow** - Automated checks maintain quality
4. **Keep action updated** - Use latest stable version
5. **Monitor workflow runs** - Check Actions tab periodically for issues

## Integration with Branch Protection

### Enabling Required Checks

**To require markdown linting before merge:**

1. Navigate to repository Settings
2. Click Branches
3. Add branch protection rule for `main`
4. Enable "Require status checks to pass before merging"
5. Select "Markdown Lint" from available checks
6. Save changes

**Effect:**

- PRs cannot be merged if markdown linting fails
- Forces contributors to fix issues before merge
- Maintains documentation quality standards

### Recommended Protection Settings

```text
[x] Require status checks to pass before merging
  [x] Require branches to be up to date before merging
  [x] Markdown Lint (selected check)
[x] Require conversation resolution before merging
```

## Resources

- **markdownlint-cli2-action:** [github.com/DavidAnson/markdownlint-cli2-action](https://github.com/DavidAnson/markdownlint-cli2-action)
- **GitHub Actions Documentation:** [docs.github.com/actions](https://docs.github.com/en/actions)
- **Workflow Syntax:** [docs.github.com/actions/reference/workflow-syntax-for-github-actions](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- **Branch Protection:** [docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)

---

**Last Verified:** 2025-11-25
