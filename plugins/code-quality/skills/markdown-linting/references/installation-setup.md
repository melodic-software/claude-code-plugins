# Installation and Setup

This guide walks you through setting up markdown linting in any repository or project, from first-time installation to full configuration.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Setup Check](#quick-setup-check)
- [Two Approaches: npx vs Local Install](#two-approaches-npx-vs-local-install)
- [Option 1: npx (Zero Setup)](#option-1-npx-zero-setup)
- [Option 2: Local Install (Full Setup)](#option-2-local-install-full-setup)
- [Configuration File Setup (Complete)](#configuration-file-setup-complete)
- [Verification Steps](#verification-steps)
- [Troubleshooting Setup Issues](#troubleshooting-setup-issues)
- [Next Steps](#next-steps)
- [Summary: Your Setup Path](#summary-your-setup-path)

## Prerequisites

Before setting up markdown linting, ensure you have:

- **Node.js** version 18.x or higher (check: `node --version`)
- **npm** version 8.x or higher (check: `npm --version`)

If you don't have Node.js/npm installed, visit [nodejs.org](https://nodejs.org/) for installation instructions.

## Quick Setup Check

Before proceeding, check what's already configured in your project:

```bash
# Check if package.json exists
ls package.json

# Check if markdownlint-cli2 is installed locally
npm list markdownlint-cli2

# Check if .markdownlint-cli2.jsonc configuration exists
ls .markdownlint-cli2.jsonc

# Check if npm scripts are configured
cat package.json | grep "lint:md"
```

**Detection Checklist:**

- [ ] `package.json` exists
- [ ] `markdownlint-cli2` is installed (locally or globally)
- [ ] `.markdownlint-cli2.jsonc` configuration file exists
- [ ] npm scripts for linting are configured
- [ ] VS Code extension is installed (optional)
- [ ] GitHub Actions workflow exists (optional)

Use this checklist to determine which setup steps you need to complete.

## Two Approaches: npx vs Local Install

There are two equally valid approaches to using markdownlint-cli2. Choose based on your project needs:

| Approach          | Best For                                          | Pros                                                                      | Cons                                                                                 |
|-------------------|---------------------------------------------------|---------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| **npx**           | Quick checks, projects without npm, one-off usage | Zero setup, always uses latest version, no dependencies to manage         | Slower execution (downloads on each run), no custom scripts, requires internet       |
| **Local Install** | Regular use, CI/CD, team projects                 | Fast execution, offline capable, custom npm scripts, version control      | Setup required, dependencies to manage, package.json needed                          |

**General Recommendation:**

- **Start with npx** for immediate usage without setup
- **Graduate to local install** if you're linting regularly or setting up for a team

Both approaches are covered below.

---

## Option 1: npx (Zero Setup)

**Use Case:** Quick markdown checks without any installation or configuration.

### Basic Usage

Lint all markdown files in your project:

```bash
npx markdownlint-cli2 "**/*.md"
```

Lint specific files or directories:

```bash
npx markdownlint-cli2 "README.md" "docs/**/*.md"
```

### Configuration with npx

While npx requires no installation, you can still use a configuration file. Create `.markdownlint-cli2.jsonc` in your project root (see "Configuration File Setup" section below), then run:

```bash
npx markdownlint-cli2 "**/*.md"
```

markdownlint-cli2 will automatically detect and use `.markdownlint-cli2.jsonc`.

### Limitations

- Runs slower (downloads package on each invocation)
- Requires internet connection
- Cannot create custom npm scripts
- No version pinning (always uses latest)

**When to switch to local install:** If you're running linting regularly (multiple times per day), the overhead of npx becomes noticeable. Local install is faster and works offline.

---

## Option 2: Local Install (Full Setup)

**Use Case:** Regular usage, team projects, CI/CD integration, custom npm scripts.

### Step 1: Initialize npm (if needed)

If your project doesn't have a `package.json`:

```bash
npm init -y
```

This creates a basic `package.json` file.

### Step 2: Install markdownlint-cli2

Install as a dev dependency:

```bash
npm install --save-dev markdownlint-cli2
```

**Recommended version:** 0.18.1 or higher

### Step 3: Add npm Scripts

Edit `package.json` and add these scripts under the `"scripts"` section:

```json
{
  "scripts": {
    "lint:md": "markdownlint-cli2 \"**/*.md\"",
    "lint:md:fix": "markdownlint-cli2 \"**/*.md\" --fix"
  }
}
```

**If package.json already has scripts**, add these alongside existing ones:

```json
{
  "scripts": {
    "start": "node index.js",
    "test": "jest",
    "lint:md": "markdownlint-cli2 \"**/*.md\"",
    "lint:md:fix": "markdownlint-cli2 \"**/*.md\" --fix"
  }
}
```

### Step 4: Verify Installation

Check that markdownlint-cli2 is installed:

```bash
npm list markdownlint-cli2
```

Expected output:

```text
your-project@1.0.0 /path/to/your-project
└── markdownlint-cli2@0.18.1
```

### Step 5: Run Linting

Use npm scripts to lint your markdown files:

```bash
# Check all markdown files
npm run lint:md

# Auto-fix issues where possible
npm run lint:md:fix
```

---

## Configuration File Setup

Both npx and local install can use a configuration file to customize linting rules.

### Automatic Configuration Creation

**Check if configuration exists:**

```bash
ls .markdownlint-cli2.jsonc
```

**If missing**, create `.markdownlint-cli2.jsonc` in your project root with these recommended defaults:

```json
{
  "default": true,
  "MD013": false
}
```

**What this does:**

- `"default": true` - Enables all default markdownlint rules
- `"MD013": false` - Disables line-length rule (often too strict for documentation)

### Manual Configuration Creation

**Option A: Create file manually (recommended):**

1. Create a file named `.markdownlint-cli2.jsonc` in your project root
2. Add the complete configuration shown above (with `gitignore`, `ignores`, and `config` properties)
3. Save the file

**Option B: Use echo (minimal config):**

```bash
cat > .markdownlint-cli2.jsonc << 'EOF'
{
  "gitignore": true,
  "ignores": [],
  "config": {
    "default": true,
    "MD013": false
  }
}
EOF
```

**Note:** Option A is recommended for adding comments and maintaining readability.

### Customizing Rules

For a full list of available rules and customization options, see the [Markdownlint Rules Reference](markdownlint-rules.md).

**Common customizations:**

```json
{
  "default": true,
  "MD013": false,
  "MD033": false,
  "MD041": false
}
```

- `MD013` - Line length (disabled: allows long lines)
- `MD033` - Inline HTML (disabled: allows HTML in markdown)
- `MD041` - First line heading (disabled: allows non-heading first lines)

### Verification

After creating the configuration, verify it's being used:

```bash
# With npx
npx markdownlint-cli2 "README.md"

# With local install
npm run lint:md
```

If configured correctly, you should see linting output with rules applied according to your `.markdownlint-cli2.jsonc`.

---

## Configuration File Setup (Complete)

### Single Source of Truth

As of markdownlint-cli2 v0.18+ and VS Code markdownlint extension v0.55+ (2024), the recommended approach uses a **single configuration file** that contains all settings:

**`.markdownlint-cli2.jsonc` is the single source of truth** containing all configuration.

### Why One Configuration File?

The `.markdownlint-cli2.jsonc` file provides:

1. **Single source of truth**: All settings (rules, ignores, options) in one place
2. **Highest precedence**: VS Code extension uses this file first (before .markdownlint-cli2.jsonc or VS Code settings)
3. **Complete control**: Supports rules, ignores, gitignore, custom rules, formatters
4. **Comments support**: JSONC format allows inline comments for documentation
5. **Consistent behavior**: Same configuration used by CLI and VS Code extension

### Creating .markdownlint-cli2.jsonc

Create `.markdownlint-cli2.jsonc` in your project root with all configuration:

**Complete example:**

```jsonc
// .markdownlint-cli2.jsonc
{
  // Automatically respect .gitignore patterns
  "gitignore": true,

  // Additional files/patterns to ignore
  "ignores": [
    // Temporary files (ephemeral, not committed)
    ".claude/temp/**",

    // Cached official documentation (verbatim copies, should not be modified)
    // Example: ".claude/skills/*/references/official-documentation/**"
  ],

  // Linting rules configuration
  "config": {
    "default": true,   // Enable all default markdownlint rules
    "MD013": false     // Disable line-length rule (often too strict for documentation)
  }
}
```

**What each section does:**

- `gitignore`: Automatically excludes files/directories from `.gitignore`
- `ignores`: Additional glob patterns to exclude (for committed files)
- `config`: Linting rules (which MD rules are enabled/disabled)

### Configuration Precedence

When VS Code extension or markdownlint-cli2 looks for configuration, it uses this order:

1. **`.markdownlint-cli2.{jsonc,yaml,cjs}`** <- **Single source of truth (use this)**
2. `.markdownlint.{jsonc,json,yaml,yml,cjs}` (fallback if cli2 file missing)
3. VS Code user/workspace settings (avoid - not portable)

**Recommendation:** Use `.markdownlint-cli2.jsonc` for all projects to ensure consistent behavior.

### Using the gitignore Option

**Recommended approach:** Enable automatic gitignore support:

```jsonc
{
  "gitignore": true
}
```

**What this does:**

- Automatically excludes any files/directories listed in `.gitignore`
- Works recursively (respects `.gitignore` files in subdirectories)
- No need to manually list patterns like `node_modules`, `vendor`, build artifacts, etc.

**Example:** If your `.gitignore` contains:

```gitignore
node_modules/
.cache/
dist/
.temp/
```

All markdown files in those directories are automatically excluded from linting.

### Using the ignores Option

Use `ignores` for files/directories that should not be linted:

```jsonc
{
  "gitignore": true,
  "ignores": [
    // Temporary files (ephemeral, may not be gitignored)
    ".claude/temp/**",

    // Cached official documentation (exact copies, should not be modified)
    // Example: ".claude/skills/*/references/official-documentation/**",
    "docs/external/**",

    // Generated documentation
    "docs/api/auto-generated-*.md",

    // Archived content
    "archive/**/*.md"
  ]
}
```

**When to use ignores:**

- Temporary files not covered by .gitignore
- Files committed to repo but shouldn't be linted (third-party docs, cached content)
- Generated files that don't follow style rules
- Archived content not worth fixing
- Directories containing verbatim copies of external documentation

**When to use gitignore:**

- Temporary files, build artifacts, dependencies
- Files not committed to repository

### Using the config Option

The `config` property contains all linting rules:

```jsonc
{
  "config": {
    "default": true,      // Enable all default rules
    "MD013": false,       // Disable specific rule
    "MD003": {            // Configure rule with options
      "style": "atx"
    }
  }
}
```

**Common rule customizations:**

- `MD013: false` - Disable line-length limit (often too strict)
- `MD033: false` - Allow inline HTML in markdown
- `MD041: false` - Allow files to start with non-heading content

For all available rules, see [markdownlint Rules Documentation](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md).

### Complete Configuration Example

**Project structure:**

```text
my-project/
├── .gitignore                    # Git exclusions
├── .markdownlint-cli2.jsonc      # Single source of truth
├── docs/
│   ├── guide.md                  # Linted
│   ├── api-reference.md          # Linted
│   └── external/
│       └── third-party.md        # Ignored (via ignores)
├── node_modules/                 # Ignored (via gitignore)
└── README.md                     # Linted
```

**.gitignore:**

```gitignore
node_modules/
dist/
.cache/
.temp/
```

**.markdownlint-cli2.jsonc:**

```jsonc
// Single source of truth for markdown linting
// Used by both markdownlint-cli2 CLI and VS Code extension
{
  // Automatically respect .gitignore patterns
  "gitignore": true,

  // Additional files to ignore (committed but shouldn't be linted)
  "ignores": [
    "docs/external/third-party.md"
  ],

  // Linting rules configuration
  "config": {
    "default": true,
    "MD013": false,
    "MD033": false
  }
}
```

**Result:**

- **Linted**: `README.md`, `docs/guide.md`, `docs/api-reference.md`
- **Ignored (gitignore)**: `node_modules/`, `dist/`, `.cache/`, `.temp/`
- **Ignored (explicit)**: `docs/external/third-party.md`

### VS Code Extension Compatibility

**`.markdownlint-cli2.jsonc` works seamlessly with VS Code:**

- VS Code extension reads this file with highest precedence
- All settings (rules, ignores, options) apply automatically
- No VS Code settings.json configuration needed
- Configuration is identical between CLI and editor

**Deprecated:** The `markdownlint.ignore` VS Code setting was removed in v0.55 (2024). Use `.markdownlint-cli2.jsonc` instead.

### Verifying Configuration

**Check which files are being ignored:**

```bash
npx markdownlint-cli2 "**/*.md"
```

**Output shows excluded files with `!` prefix:**

```text
Finding: **/*.md !node_modules/** !docs/external/third-party.md
Linting: 42 file(s)
```

**Verify configuration is being read:**

```bash
# Check if file exists
ls .markdownlint-cli2.jsonc

# Validate JSON syntax
node -e "console.log(JSON.parse(require('fs').readFileSync('.markdownlint-cli2.jsonc', 'utf-8')))"
```

### Migration from Two-File Approach

**If you have both `.markdownlint.json` and `.markdownlint-cli2.jsonc`:**

1. **Consolidate** rules from `.markdownlint.json` into `config` property of `.markdownlint-cli2.jsonc`
2. **Delete** `.markdownlint.json` file
3. **Test** that linting still works correctly

**Migration example:**

**Before (two files):**

`.markdownlint.json`:

```json
{
  "default": true,
  "MD013": false
}
```

`.markdownlint-cli2.jsonc`:

```jsonc
{
  "gitignore": true,
  "ignores": ["vendor/**/*.md"]
}
```

**After (one file):**

`.markdownlint-cli2.jsonc`:

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

### Troubleshooting Configuration

**Files are still being linted despite being in ignores:**

```bash
# Check configuration file syntax
cat .markdownlint-cli2.jsonc

# Verify valid JSONC
node -e "console.log(JSON.parse(require('fs').readFileSync('.markdownlint-cli2.jsonc', 'utf-8')))"
```

**Common issues:**

- Incorrect glob pattern (use `**` for recursive, `*` for single level)
- Configuration file in wrong location (must be in project root)
- Syntax error in JSONC (missing comma, trailing comma, etc.)
- Using relative paths instead of glob patterns

**Correct glob patterns:**

```jsonc
{
  "ignores": [
    "vendor/**/*.md",           // All .md files in vendor/ recursively
    "**/node_modules/**",       // node_modules anywhere
    "docs/archive/*.md",        // Only .md files in docs/archive/
    "*.md"                      // All .md files in root directory
  ]
}
```

**Incorrect patterns:**

```jsonc
{
  "ignores": [
    "./vendor/**/*.md",         // Don't use ./
    "../docs/*.md",             // Don't use ../
    "C:/repos/project/docs/*.md" // Don't use absolute paths
  ]
}
```

**Rules not being applied:**

- Verify `config` property exists in `.markdownlint-cli2.jsonc`
- Check for syntax errors (missing commas, trailing commas)
- Ensure VS Code extension is installed and active
- Try reloading VS Code window (`Ctrl+Shift+P` -> "Reload Window")

### Minimal Setup (Recommended)

**For most projects, this minimal configuration is sufficient:**

```jsonc
// .markdownlint-cli2.jsonc
{
  "gitignore": true,
  "config": {
    "default": true,
    "MD013": false
  }
}
```

This gives you:

- All default linting rules (except line length)
- Automatic exclusion of gitignored files
- Works in both CLI and VS Code
- Single source of truth
- Clean, maintainable configuration

### References

- [markdownlint-cli2 Configuration Docs](https://github.com/DavidAnson/markdownlint-cli2#configuration)
- [VS Code markdownlint Extension](https://github.com/DavidAnson/vscode-markdownlint)
- [markdownlint Rules Documentation](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md)

---

## Verification Steps

After setup, verify everything is working:

### 1. Create a Test File

Create `test-lint.md` with intentional issues:

```bash
echo "# Test\n\nThis is a test file.\n\n\n\n\nToo many blank lines above." > test-lint.md
```

### 2. Run Linting

**With npx:**

```bash
npx markdownlint-cli2 "test-lint.md"
```

**With local install:**

```bash
npm run lint:md
```

### 3. Expected Output

You should see warnings like:

```text
test-lint.md:7:1 MD012/no-multiple-blanks Multiple consecutive blank lines [Expected: 1, Actual: 5]
```

### 4. Test Auto-fix

**With npx:**

```bash
npx markdownlint-cli2 "test-lint.md" --fix
```

**With local install:**

```bash
npm run lint:md:fix
```

Check `test-lint.md` - the extra blank lines should be removed.

### 5. Clean Up

```bash
rm test-lint.md
```

---

## Troubleshooting Setup Issues

### "command not found: npx"

**Cause:** Node.js/npm not installed or not in PATH.

**Solution:**

1. Install Node.js from [nodejs.org](https://nodejs.org/)
2. Verify installation: `node --version` and `npm --version`
3. Restart your terminal

### "Cannot find module 'markdownlint-cli2'"

**Cause:** markdownlint-cli2 not installed locally, but you're trying to use npm scripts.

**Solution:**

```bash
npm install --save-dev markdownlint-cli2
```

### "package.json not found"

**Cause:** Trying to run `npm install` or `npm run` without a package.json.

**Solution:**

```bash
npm init -y
```

Then proceed with local install steps.

### "No such file or directory: .markdownlint-cli2.jsonc"

**Cause:** This is NOT an error. markdownlint-cli2 works without a config file (uses default rules).

**To customize rules:** Create `.markdownlint-cli2.jsonc` as shown in "Configuration File Setup" section.

### Configuration file not being read

**Verify configuration file location:**

```bash
# Should be in project root
ls -la .markdownlint-cli2.jsonc
```

**Check file syntax:**

```bash
# Valid JSON?
cat .markdownlint-cli2.jsonc | node -e "console.log(JSON.parse(require('fs').readFileSync(0, 'utf-8')))"
```

If there's a syntax error, fix the JSON and re-run linting.

---

## Next Steps

Once you have basic CLI linting working, consider these optional enhancements:

### VS Code Integration (Optional)

Set up real-time linting in your editor. See [VS Code Extension Setup](vscode-extension-setup.md).

**Benefits:**

- See linting errors as you type
- Auto-fix on save
- Inline error descriptions

### GitHub Actions CI/CD (Optional)

Enforce linting in pull requests and CI pipelines. See [GitHub Actions Configuration](github-actions-config.md).

**Benefits:**

- Prevent commits with linting errors
- Automated checks on every PR
- Team-wide quality enforcement

### Custom Scripts (Optional)

Create additional npm scripts for specific use cases. See [Scripts Reference](../scripts/README.md).

**Examples:**

- Lint only docs folder
- Lint only changed files
- Pre-commit hooks

---

## Summary: Your Setup Path

**Just want to try it?**
-> Use npx: `npx markdownlint-cli2 "**/*.md"`

**Setting up for regular use?**
-> Local install: `npm install --save-dev markdownlint-cli2`, add npm scripts

**Want to customize rules?**
-> Create `.markdownlint-cli2.jsonc` in project root

**Ready for team/CI use?**
-> See VS Code integration and GitHub Actions guides

**Need help?**
-> Check [Troubleshooting Setup Issues](#troubleshooting-setup-issues) above

---

**Last Verified:** 2025-11-25
