# Markdown Linting Automation Scripts

This directory documents current markdown linting automation options and potential future enhancements.

## Current Automation Options

### NPM Scripts (Optional)

If you're using the local install approach, you can add npm scripts to `package.json` for convenient linting commands.

**Check if you have `package.json`:**

```bash
ls package.json
```

**If missing, create it:**

```bash
npm init -y
```

**Add these scripts to the `"scripts"` section of `package.json`:**

```json
{
  "scripts": {
    "lint:md": "markdownlint-cli2 \"**/*.md\" \"#node_modules\"",
    "lint:md:fix": "markdownlint-cli2 --fix \"**/*.md\" \"#node_modules\""
  }
}
```

**Note:** If you prefer using npx (zero setup), you don't need npm scripts. See the [Installation Setup Guide](../references/installation-setup.md) for npx usage.

#### `npm run lint:md`

**Purpose:** Check all markdown files for linting errors

**Command:** `markdownlint-cli2 "**/*.md" "#node_modules"`

**What it does:**

- Recursively checks all `.md` files in the project
- Excludes `node_modules` directory
- Reports errors with file paths, line numbers, and rule violations
- Exit code 0 if no errors, non-zero if errors found

**Usage:**

```bash
# With npm scripts (if configured)
npm run lint:md

# Or with npx (no setup required)
npx markdownlint-cli2 "**/*.md"
```

**Example output:**

```text
docs/setup-guide.md:45:1 MD022/blanks-around-headings Headings should be surrounded by blank lines
README.md:12:81 MD009/no-trailing-spaces Trailing spaces
```

#### `npm run lint:md:fix`

**Purpose:** Automatically fix fixable markdown linting errors

**Command:** `markdownlint-cli2 --fix "**/*.md" "#node_modules"`

**What it does:**

- Recursively checks all `.md` files
- Automatically fixes issues that can be safely corrected
- Modifies files in place
- Reports remaining unfixable issues

**Usage:**

```bash
# With npm scripts (if configured)
npm run lint:md:fix

# Or with npx (no setup required)
npx markdownlint-cli2 "**/*.md" --fix
```

**Fixable issues:**

- Trailing spaces (MD009)
- Missing blank lines (MD012, MD022)
- List marker consistency (MD004, MD007)
- Code fence style (MD048)

**Non-fixable issues (require manual correction):**

- Heading structure (MD001, MD025)
- Inline HTML (MD033)
- Link references (MD051, MD052)

### VS Code Integration (Optional)

For real-time linting in VS Code, you can configure auto-fix on save.

**Create `.vscode/settings.json` in your project root (if it doesn't exist):**

```bash
mkdir -p .vscode
echo '{}' > .vscode/settings.json
```

**Add this configuration to `.vscode/settings.json`:**

```json
{
  "[markdown]": {
    "editor.formatOnSave": true,
    "editor.formatOnPaste": true
  },
  "editor.codeActionsOnSave": {
    "source.fixAll.markdownlint": "explicit"
  }
}
```

**What this provides:**

- Automatic linting as you type
- Auto-fix on save
- Auto-fix on paste
- Real-time visual feedback

See the [VS Code Extension Setup Guide](../references/vscode-extension-setup.md) for comprehensive setup instructions.

### GitHub Actions (Optional)

For automated linting in CI/CD, you can set up a GitHub Actions workflow.

**Create `.github/workflows/markdown-lint.yml` in your project:**

See the [GitHub Actions Configuration Guide](../references/github-actions-config.md) for comprehensive setup instructions.

**Example triggers:**

- Pull requests that modify `.md` files
- Pushes to `main` branch that modify `.md` files

**What it does:** Runs `markdownlint-cli2` against all markdown files automatically

**Result:** Pass/fail check on PRs and commits

## Future Automation Possibilities

**Note:** The following are potential future enhancements, not currently implemented.

### 1. Pre-Commit Hooks

**Purpose:** Prevent committing markdown files with linting errors

**Implementation options:**

#### Option A: Husky + lint-staged

```bash
# Install dependencies
npm install --save-dev husky lint-staged

# Initialize husky
npx husky install

# Create pre-commit hook
npx husky add .husky/pre-commit "npx lint-staged"
```

**Configuration in `package.json`:**

```json
{
  "lint-staged": {
    "*.md": "markdownlint-cli2 --fix"
  }
}
```

**Benefits:**

- Automatic linting before each commit
- Only lints staged files (fast)
- Auto-fixes issues during commit
- Prevents broken commits from being created

**Considerations:**

- Adds friction to commit process
- May be frustrating if linting is slow
- Some developers may find it intrusive

#### Option B: Simple Git Hook

```bash
#!/bin/sh
# .git/hooks/pre-commit

echo "Running markdown linting..."
npm run lint:md

if [ $? -ne 0 ]; then
  echo "Markdown linting failed. Fix errors or use --no-verify to bypass."
  exit 1
fi
```

**Benefits:**

- Simple to implement
- No additional dependencies
- Easy to understand

**Considerations:**

- Not committed to repository (manual setup required)
- Checks all files (slower than staged-only)

### 2. Batch Validation Scripts

#### Script: Lint Modified Files Only

**File:** `scripts/lint-modified.sh`

```bash
#!/bin/bash
# Lint only files modified since last commit

git diff --name-only --diff-filter=AM HEAD | grep '\.md$' | xargs markdownlint-cli2
```

**Benefits:**

- Faster than linting all files
- Useful for large repositories
- Focus on recent changes

### 3. CI/CD Enhancements

#### Progressive Enforcement

**Concept:** Fail fast on critical rules, warn on others

```yaml
# .github/workflows/markdown-lint.yml
- name: Check critical rules (fail on error)
  uses: DavidAnson/markdownlint-cli2-action@v21
  with:
    config: .markdownlint-cli2-critical.jsonc
    globs: '**/*.md'

- name: Check all rules (warn only)
  uses: DavidAnson/markdownlint-cli2-action@v21
  continue-on-error: true
  with:
    globs: '**/*.md'
```

**Benefits:**

- Don't block PRs on minor issues
- Gradually increase standards
- Educate without frustrating

## Implementation Guidance

When adding new automation scripts to your project:

1. **Follow established patterns:**
   - Use consistent naming conventions
   - Include comprehensive error handling
   - Provide clear, actionable error messages

2. **Document thoroughly:**
   - Add usage instructions to script comments
   - Update this README.md with script details (or your project's docs)
   - Provide examples and expected output

3. **Test before committing:**
   - Verify scripts work in target environments
   - Test edge cases and error conditions
   - Ensure cross-platform compatibility (if needed)

4. **Make executable:**
   - Set execute permissions: `chmod +x scripts/script-name.sh`
   - Add shebang line: `#!/bin/bash` or `#!/usr/bin/env python3`

5. **Document in your project:**
   - Note any new dependencies
   - Document prerequisites or setup required
   - Update any relevant documentation

## Resources

- **markdownlint-cli2 Documentation:** [github.com/DavidAnson/markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2)
- **Husky (Git hooks):** [typicode.github.io/husky](https://typicode.github.io/husky)
- **lint-staged:** [github.com/okonet/lint-staged](https://github.com/okonet/lint-staged)
- **GitHub Actions:** [docs.github.com/actions](https://docs.github.com/en/actions)
