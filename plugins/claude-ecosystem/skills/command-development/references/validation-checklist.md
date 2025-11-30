# Slash Command Validation Checklist

**Source:** Official Claude Code documentation (code.claude.com)

Use this checklist before creating custom slash commands. All rules are extracted from official documentation.

## File Structure

### Location

- [ ] **Project commands:** `.claude/commands/` directory
- [ ] **Personal commands:** `~/.claude/commands/` directory
- [ ] **Plugin commands:** Plugin's `commands/` directory (auto-namespaced)

### File Naming

- [ ] **Use `.md` extension**
- [ ] **File name becomes command name** (without `.md`)
- [ ] **Kebab-case recommended** (e.g., `review-code.md`)
- [ ] **Subdirectories for organization** (don't affect command name)

**Examples:**
- `.claude/commands/review.md` → `/review`
- `.claude/commands/frontend/component.md` → `/component` (description shows "(project:frontend)")

## YAML Frontmatter (Optional but Recommended)

### `description` Field

- [ ] **Clear, concise description** of what the command does
- [ ] **Shown in command list** and autocomplete
- [ ] **Helps users understand command purpose**

### `allowed-tools` Field

- [ ] **Restrict available tools** if needed
- [ ] **Comma-separated list** of tool names
- [ ] **Omit for default tool access**

**Example:**
```yaml
---
description: Review code for quality and suggest improvements
allowed-tools: Read, Glob, Grep
---
```

## Command Body

### Content Format

- [ ] **Markdown format**
- [ ] **Plain text instructions** for Claude
- [ ] **Can include templates** and examples

### Arguments

- [ ] **`$ARGUMENTS`** - Full argument string
- [ ] **`$1`, `$2`, etc.** - Positional arguments
- [ ] **Arguments are optional** - command works without them

**Example:**
```markdown
Review the code in $1 for:
- Code quality
- Potential bugs
- Performance issues
```

### File References

- [ ] **Use `@filename`** to include file content
- [ ] **Paths relative to project root**
- [ ] **Files included verbatim**

## Plugin Command Namespacing

- [ ] **Auto-namespaced:** `plugin-name:command-name`
- [ ] **Direct invocation possible** when no conflicts
- [ ] **Namespace required** when command names conflict across plugins

**Example:**
- Plugin: `claude-ecosystem`
- Command file: `commands/scrape-docs.md`
- Invocation: `/claude-ecosystem:scrape-docs` or just `/scrape-docs` if unique

## Pre-Creation Verification

Before creating a new command:

1. [ ] Check command name is unique (or accept namespace prefix)
2. [ ] Description clearly explains purpose
3. [ ] Tool restrictions appropriate for command's scope
4. [ ] Arguments documented if expected
5. [ ] File references use correct paths

## Common Mistakes to Avoid

- Forgetting `.md` extension
- Assuming subdirectory affects command name
- Not providing description (harder for users to discover)
- Over-restricting or under-restricting tools
- Using absolute paths in file references

---

**Last Updated:** 2025-11-30
**Source References:**
- `code-claude-com/docs/en/slash-commands.md`
