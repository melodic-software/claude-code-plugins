# VS Code Extension Setup Guide

**Optional/Advanced:** This guide is for setting up real-time markdown linting in your editor. **You do NOT need this to use markdownlint** - CLI linting (npx or npm scripts) works without VS Code integration.

**Benefits of VS Code integration:**

- Real-time linting as you type
- Visual indicators for violations
- Auto-fix on save capability
- Quick fixes with keyboard shortcuts

Extended guide for setting up and configuring the markdownlint VS Code extension.

## Table of Contents

- [Extension Information](#extension-information)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)
- [Best Practices](#best-practices)
- [Resources](#resources)

## Extension Information

- **Name:** markdownlint
- **Publisher:** David Anson
- **ID:** `davidanson.vscode-markdownlint`
- **Marketplace:** [marketplace.visualstudio.com/items?itemName=DavidAnson.vscode-markdownlint](https://marketplace.visualstudio.com/items?itemName=DavidAnson.vscode-markdownlint)

## Installation

### Method 1: VS Code Marketplace (GUI)

1. Open VS Code
2. Click Extensions icon in sidebar (or press `Ctrl+Shift+X` / `Shift+Cmd+X`)
3. Search for `markdownlint`
4. Find **"markdownlint"** by David Anson
5. Click **Install**

### Method 2: Command Line

```bash
code --install-extension davidanson.vscode-markdownlint
```

### Verification

After installation, verify the extension is active:

1. Open any `.md` file
2. Open Command Palette (`Ctrl+Shift+P` / `Shift+Cmd+P`)
3. Type "markdownlint"
4. You should see commands like "markdownlint: Fix all supported markdownlint violations in the document"

## Configuration

### Project Configuration Setup (Optional)

To enable auto-fix on save and other convenience features, create or update `.vscode/settings.json` in your project root:

**Check if file exists:**

```bash
ls .vscode/settings.json
```

**If missing, create `.vscode/` directory and `settings.json` file:**

```bash
mkdir .vscode
echo '{}' > .vscode/settings.json
```

**Add recommended configuration to `.vscode/settings.json`:**

```json
{
  "markdown.validate.enabled": true,
  "[markdown]": {
    "editor.formatOnSave": true,
    "editor.formatOnPaste": true
  },
  "editor.codeActionsOnSave": {
    "source.fixAll.markdownlint": "explicit"
  }
}
```

**What this configuration does:**

- `markdown.validate.enabled: true` - Enables built-in markdown validation
- `editor.formatOnSave: true` - Automatically formats markdown files on save
- `editor.formatOnPaste: true` - Automatically formats pasted markdown content
- `source.fixAll.markdownlint: "explicit"` - Runs markdownlint auto-fix on save

**Tip:** Commit `.vscode/settings.json` to your project repository so these settings apply to all team members automatically.

### Linting Rules Configuration

The extension automatically reads `.markdownlint-cli2.jsonc` in the project root as the single source of truth:

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

**If you don't have a `.markdownlint-cli2.jsonc` file yet**, see the [Installation and Setup Guide](installation-setup.md) for instructions on creating one.

**Configuration precedence** (highest to lowest):

1. `.markdownlint-cli2.{jsonc,yaml,cjs}` file <- **Single source of truth (recommended)**
2. `.markdownlint.{jsonc,json,yaml,yml,cjs}` file (deprecated, use `.markdownlint-cli2.jsonc` instead)
3. VS Code user settings (`settings.json`)
4. VS Code workspace settings (`.vscode/settings.json`)
5. Default configuration

**Recommendation:** Always use project-level `.markdownlint-cli2.jsonc` for portability and highest precedence. Avoid user-specific settings that won't apply to other team members.

## Usage

### Real-Time Linting

The extension lints markdown files automatically as you type:

1. **Visual indicators:**
   - Green squiggly underlines appear under violations
   - Severity icons in the gutter (left margin)
   - Problem count in status bar

2. **Viewing violations:**
   - Hover over underlined text to see rule details
   - Check Problems panel (`Ctrl+Shift+M` / `Shift+Cmd+M`) for full list
   - Click on problem to jump to location

3. **Example:**
   - Type a heading without blank lines around it
   - Green squiggles appear
   - Hover to see: "MD022/blanks-around-headings: Headings should be surrounded by blank lines"

### Auto-Fix Methods

#### Method 1: Auto-Fix on Save (Automatic)

**If configured in `.vscode/settings.json`:**

- Save file (`Ctrl+S` / `Cmd+S`)
- Fixable issues are corrected automatically
- Non-fixable issues remain for manual correction
- Only works if auto-fix on save is configured (see Configuration section above)

#### Method 2: Format Document Command

**Keyboard shortcuts:**

- Windows/Linux: `Shift+Alt+F` or `Ctrl+Shift+I`
- macOS: `Shift+Option+F`

**What happens:**

- All fixable markdownlint issues are corrected
- Other formatters may also run (if configured)
- Entire document is processed

#### Method 3: Format Selection Command

**Keyboard shortcuts:**

- Windows/Linux: `Ctrl+K Ctrl+F`
- macOS: `Cmd+K Cmd+F`

**What happens:**

- Only selected text is formatted
- Fixable markdownlint issues in selection are corrected
- Useful for fixing specific sections

#### Method 4: Fix All Command (markdownlint-specific)

**Steps:**

1. Open Command Palette (`Ctrl+Shift+P` / `Shift+Cmd+P`)
2. Type: `markdownlint fix`
3. Select: "markdownlint: Fix all supported markdownlint violations in the document"

**What happens:**

- Only markdownlint fixes are applied
- Other formatters are NOT run
- Most specific to markdownlint corrections

#### Method 5: Quick Fix (Single Issue)

**Steps:**

1. Place cursor on green squiggly underline
2. Press `Ctrl+.` (Windows/Linux) or `Cmd+.` (macOS)
3. Select suggested fix from dropdown

**What happens:**

- Only the specific issue is fixed
- Useful for understanding and learning rules
- Allows selective fixing

### Interactive Features

#### Problems Panel

**Open:** `Ctrl+Shift+M` (Windows/Linux) or `Shift+Cmd+M` (macOS)

**Features:**

- Lists all markdownlint violations in current file
- Filter by file, severity, or rule
- Click on problem to jump to location
- Right-click for quick fixes

#### Hover Information

**Usage:** Hover mouse over green squiggly underline

**Displays:**

- Rule number (e.g., MD022)
- Rule name (e.g., blanks-around-headings)
- Brief description
- Link to official documentation (clickable)

#### Code Actions

**Usage:** Place cursor on violation, press `Ctrl+.` / `Cmd+.`

**Displays:**

- Available quick fixes
- Option to disable rule (inline comment)
- Option to ignore violation

**Example:**

```text
Quick Fix: Add blank line before heading
Suppress: Add <!-- markdownlint-disable MD022 --> comment
```

## Troubleshooting

### Extension Not Linting Files

**Possible causes:**

1. Extension not installed or disabled
2. File not recognized as markdown
3. Configuration file syntax error
4. Extension error

**Solutions:**

1. **Verify installation:**
   - Check Extensions panel
   - Look for "markdownlint" by David Anson
   - Ensure it's enabled (not grayed out)

2. **Check file type:**
   - Bottom-right corner should show "Markdown"
   - If not, click language indicator and select "Markdown"
   - Ensure file has `.md` extension

3. **Validate configuration:**
   - Open `.markdownlint-cli2.jsonc`
   - Verify valid JSON syntax (JSONC allows comments and trailing commas)
   - Check for typos in rule names

4. **Check extension logs:**
   - Open Output panel (`Ctrl+Shift+U` / `Shift+Cmd+U`)
   - Select "markdownlint" from dropdown
   - Look for error messages

5. **Reload VS Code:**
   - Command Palette -> "Developer: Reload Window"
   - Or restart VS Code entirely

### Auto-Fix Not Working on Save

**Possible causes:**

1. `.vscode/settings.json` not configured
2. User settings overriding project settings
3. `editor.formatOnSave` disabled globally
4. Extension error

**Solutions:**

1. **Verify project settings:**
   - Open `.vscode/settings.json` (create if missing - see Configuration section)
   - Confirm configuration matches the recommended configuration above
   - Save the file

2. **Check user settings:**
   - File -> Preferences -> Settings (or `Ctrl+,` / `Cmd+,`)
   - Search for "format on save"
   - Ensure `Editor: Format On Save` is checked
   - Check that `[markdown]` scope isn't overridden in user settings

3. **Check for conflicting formatters:**
   - Multiple markdown formatters can conflict
   - Disable other markdown extensions temporarily
   - Test if auto-fix works

4. **Test manually:**
   - Try `Shift+Alt+F` / `Shift+Option+F` to format document
   - If manual format works but auto-save doesn't, settings issue
   - If manual format fails, extension issue

### Green Squiggles Not Appearing

**Possible causes:**

1. Extension disabled
2. File not recognized as markdown
3. No actual violations present
4. Extension initialization delay

**Solutions:**

1. **Verify extension active:**
   - Check Extensions panel for "markdownlint"
   - Ensure it's enabled

2. **Force re-lint:**
   - Make a small edit and undo it
   - Save file
   - Close and reopen file

3. **Check configuration:**
   - Open `.markdownlint-cli2.jsonc`
   - Ensure rules are enabled (not all set to `false`)
   - Current config has `"default": true` in `config` property (most rules enabled)

4. **Wait for initialization:**
   - Large files may take a moment to lint
   - Check status bar for linting indicator

### Configuration Not Being Applied

**Possible causes:**

1. Configuration file syntax error
2. Configuration file not in repository root
3. Cache issue

**Solutions:**

1. **Validate JSON syntax:**
   - Open `.markdownlint-cli2.jsonc`
   - Look for red squiggles indicating syntax errors
   - JSONC format allows comments and trailing commas

2. **Verify file location:**
   - Configuration must be at project root (same directory as `.git` folder)
   - Example path: `<project-root>/.markdownlint-cli2.jsonc`

3. **Clear VS Code cache:**
   - Close VS Code
   - Delete workspace cache (varies by OS)
   - Reopen VS Code

4. **Reload window:**
   - Command Palette -> "Developer: Reload Window"

## Advanced Configuration

### Per-File Rule Overrides

Disable rules for specific files using inline comments:

```markdown
<!-- markdownlint-disable MD013 -->
# Document Title

This file allows long lines.
```

Re-enable later in the same file:

```markdown
<!-- markdownlint-enable MD013 -->
```

Disable multiple rules:

```markdown
<!-- markdownlint-disable MD013 MD033 -->
```

**Warning:** Use sparingly. Per-file overrides reduce consistency.

### Custom Keyboard Shortcuts

Add custom shortcuts in `keybindings.json`:

```json
[
  {
    "key": "ctrl+alt+l",
    "command": "markdownlint.fixAll",
    "when": "editorTextFocus && editorLangId == 'markdown'"
  }
]
```

### Extension Settings

Additional extension settings (optional, not currently used):

```json
{
  "markdownlint.config": {
    // Inline configuration (not recommended, use .markdownlint-cli2.jsonc instead)
  },
  "markdownlint.ignore": [
    // Files to ignore (deprecated as of v0.55, 2024 - use ignores in .markdownlint-cli2.jsonc instead)
  ],
  "markdownlint.run": "onType",  // When to lint: "onType" or "onSave"
  "markdownlint.focusMode": false  // Dim non-focused sections
}
```

**Recommendation:** Keep configuration in `.markdownlint-cli2.jsonc` for portability and highest precedence. Avoid extension-specific settings that won't transfer to CLI or GitHub Actions.

## Best Practices

1. **Let auto-fix handle the basics** - Don't manually fix trailing spaces, blank lines, etc.
2. **Learn from quick fixes** - Use `Ctrl+.` / `Cmd+.` to understand what's wrong
3. **Check Problems panel before committing** - Ensure no violations remain
4. **Fix content instead of disabling rules** - Prefer fixing markdown over inline rule disabling
5. **Keep extension updated** - Check for updates regularly

## Resources

- **Extension Marketplace:** [marketplace.visualstudio.com/items?itemName=DavidAnson.vscode-markdownlint](https://marketplace.visualstudio.com/items?itemName=DavidAnson.vscode-markdownlint)
- **Extension Repository:** [github.com/DavidAnson/vscode-markdownlint](https://github.com/DavidAnson/vscode-markdownlint)
- **Markdownlint Library:** [github.com/DavidAnson/markdownlint](https://github.com/DavidAnson/markdownlint)
- **VS Code Keyboard Shortcuts:** [code.visualstudio.com/docs/getstarted/keybindings](https://code.visualstudio.com/docs/getstarted/keybindings)

---

**Last Verified:** 2025-11-25
