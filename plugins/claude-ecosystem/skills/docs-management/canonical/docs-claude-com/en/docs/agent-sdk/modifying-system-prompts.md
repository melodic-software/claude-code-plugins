<!-- Source: https://docs.claude.com/en/docs/agent-sdk/modifying-system-prompts -->

# Modifying system prompts

Learn how to customize Claude's behavior by modifying system prompts using three approaches - output styles, systemPrompt with append, and custom system prompts.

System prompts define Claude's behavior, capabilities, and response style. The Claude Agent SDK provides three ways to customize system prompts: using output styles (persistent, file-based configurations), appending to Claude Code's prompt, or using a fully custom prompt.

## Understanding system prompts

A system prompt is the initial instruction set that shapes how Claude behaves throughout a conversation.

<Note>
  **Default behavior:** The Agent SDK uses an **empty system prompt** by default for maximum flexibility. To use Claude Code's system prompt (tool instructions, code guidelines, etc.), specify `systemPrompt: { preset: "claude_code" }` in TypeScript or `system_prompt="claude_code"` in Python.
</Note>

Claude Code's system prompt includes:

* Tool usage instructions and available tools
* Code style and formatting guidelines
* Response tone and verbosity settings
* Security and safety instructions
* Context about the current working directory and environment

## Methods of modification

### Method 1: CLAUDE.md files (project-level instructions)

CLAUDE.md files provide project-specific context and instructions that are automatically read by the Agent SDK when it runs in a directory. They serve as persistent "memory" for your project.

#### How CLAUDE.md works with the SDK

**Location and discovery:**

* **Project-level:** `CLAUDE.md` or `.claude/CLAUDE.md` in your working directory
* **User-level:** `~/.claude/CLAUDE.md` for global instructions across all projects

**IMPORTANT:** The SDK only reads CLAUDE.md files when you explicitly configure `settingSources` (TypeScript) or `setting_sources` (Python):

* Include `'project'` to load project-level CLAUDE.md
* Include `'user'` to load user-level CLAUDE.md (`~/.claude/CLAUDE.md`)

The `claude_code` system prompt preset does NOT automatically load CLAUDE.md - you must also specify setting sources.

**Content format:**
CLAUDE.md files use plain markdown and can contain:

* Coding guidelines and standards
* Project-specific context
* Common commands or workflows
* API conventions
* Testing requirements

#### Example CLAUDE.md

```markdown  theme={null}