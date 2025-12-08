---
description: Export Claude Code's current system prompt to console or file
argument-hint: [--output [path]] (optional)
allowed-tools: Write, Bash(date:*)
---

# Export System Prompt

Export Claude Code's complete system prompt (all instructions, tool definitions, CLAUDE.md content, memory imports, and session context) to the console or a markdown file.

## Arguments

- **No arguments**: Output formatted system prompt directly to console (default)
- **`--output`**: Write to auto-generated path in `.claude/temp/`
- **`--output <path>`**: Write to specified path (`.md` extension added if missing)

## Execution Workflow

### Step 1: Parse Arguments

1. Check if `--output` flag is present in `$ARGUMENTS`
2. If `--output` present, check if a path follows it
3. Determine output mode:
   - `console` (no flag)
   - `file_auto` (flag without path)
   - `file_custom` (flag with path)

### Step 2: Get Current Timestamp

Run: `date -u +"%Y-%m-%dT%H:%M:%SZ"` to get UTC timestamp for metadata.

### Step 3: Capture System Prompt

The "system prompt" includes everything Claude sees as instructions at the start of each turn:

- Base Claude Code system instructions
- Tool definitions and descriptions
- CLAUDE.md file contents (project instructions)
- Memory file imports (@-file references)
- Hook-injected content (`<system-reminder>` tags)
- Session-specific context (gitStatus, environment info)

**Important:** Output the COMPLETE system prompt without truncation. This is the entire context Claude operates under.

### Step 4: Format Output

Format as markdown with metadata header:

```markdown
# System Prompt Export

**Exported:** {UTC timestamp}
**Working Directory:** {cwd from environment}
**Model:** {model name from system context}

---

## Complete System Prompt

{Everything from the system context - tools, instructions, CLAUDE.md, memory, hooks, etc.}

---

*Exported by `/claude-ecosystem:export-system-prompt`*
```

### Step 5: Output Based on Mode

**Console Mode (default):**

Output the formatted markdown directly. The user will see the complete system prompt in the conversation.

**File Mode (--output):**

1. Determine output path:
   - If path provided: Use it (append `.md` if missing)
   - If no path: Generate `.claude/temp/YYYY-MM-DD_HHmmss-system-prompt-export.md`

2. Write formatted output to file using Write tool

3. Report success: `Saved system prompt to: {path}`

## Output Template

```markdown
# System Prompt Export

**Exported:** {timestamp}
**Working Directory:** {cwd}
**Model:** {model}

---

## Complete System Prompt

### Tool Definitions

{List all available tools with their descriptions}

### System Instructions

{Base Claude Code instructions}

### Project Instructions (CLAUDE.md)

{Contents of CLAUDE.md and imported memory files}

### Session Context

{gitStatus, environment info, hook-injected reminders}

---

*Exported by `/claude-ecosystem:export-system-prompt`*
```

## Verification Protocol

Before reporting completion, verify:

- [ ] Arguments parsed correctly (detected output mode)
- [ ] Timestamp captured
- [ ] Complete system prompt included (not truncated)
- [ ] Output formatted as markdown with metadata
- [ ] If file mode: File written successfully and path reported
- [ ] If console mode: Full output displayed

## Notes

- **Large output warning**: System prompts can be 10K+ tokens. For easier handling, consider using `--output` to save to a file.
- **Security awareness**: The exported prompt contains your repository's CLAUDE.md instructions and configuration. Be mindful when sharing.
- **Debugging use case**: This command is useful for understanding exactly what instructions Claude is operating under, especially when troubleshooting unexpected behavior.
