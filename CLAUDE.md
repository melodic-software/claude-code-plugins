# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See @README for project overview and installation.

## Critical Rules (Repo-Specific)

- **Use Python 3.13** for spaCy operations
- **Set plugin dev mode** when modifying plugin scripts - use env vars for local code instead of installed plugin. See `.claude/memory/plugin-dev-mode.md`
- **Use `docs-management` skill for documentation indexes** - invoke the skill to search docs rather than reading index.yaml files directly
- **MCP Server Usage**: Microsoft tech -> `microsoft-learn`, libraries -> `context7`+`ref`, general -> `perplexity`+`firecrawl`. See `.claude/memory/mcp-usage-patterns.md`
- **Git Bash on Windows**: Use `MSYS_NO_PATHCONV=1` prefix to prevent path conversion issues when running scripts

## Memory File References

- **Performance optimization**: See @.claude/memory/performance-quick-start.md
- **Context engineering**: See `.claude/memory/context-engineering.md`
- **Claude Code ecosystem**: See @.claude/memory/claude-code-ecosystem.md
- **Anti-Duplication enforcement**: See `.claude/memory/anti-duplication-enforcement.md`
- **Path conventions**: See `.claude/memory/path-conventions.md`
- **Command/Skill protocol**: See @.claude/memory/command-skill-protocol.md
- **Natural language guidance**: See @.claude/memory/natural-language-guidance.md
- **Model identification**: See `.claude/memory/model-identification.md`

## General Software Principles

- **TDD/BDD**: When adding or changing non-trivial behavior, prefer test-driven development
- **Consistency**: Use the same patterns, structures, and naming everywhere - extend existing approaches
- **Pattern-First**: Before adding docs, workflows, or structures, look for existing patterns and align to them
- **AI-Friendly Structure**: Use predictable sections (Overview, Prerequisites, Installation, Configuration, Verification, Troubleshooting)
- **Cross-Platform**: Treat Windows, macOS, and Linux as first-class - consider platform differences up front
- **ASCII Punctuation**: Use straight quotes - smart/curly quotes cause encoding issues in scripts
- **UTF-8 Encoding**: Use UTF-8 for all files, preserve Unicode, set encoding in Python scripts
- **UTC Timestamps**: Store persisted data in UTC (ISO-8601), convert to local only for display
- **DRY**: Minimize duplicated variables, magic strings, magic numbers, repeated code
- **Law of Demeter**: Minimize coupling by talking only to immediate friends
- **Best tool for the job**: Choose languages, libraries, techniques that keep solutions simple and testable

## Documentation

For Claude Code topics, invoke the `docs-management` skill.

For Gemini CLI topics, invoke the `gemini-cli-docs` skill.

## Build and Test Commands

### Running Tests

Invoke the `docs-management` skill for test instructions - it provides platform-specific commands.

### Markdown Linting

Use `/code-quality:lint-md` command or invoke the `markdown-linting` skill.

### Validate Plugin Skills

Use `/claude-ecosystem:audit-skills` command or invoke the `skill-development` skill.

## Architecture Overview

### Plugin Structure

```text
plugins/<plugin-name>/
  plugin.json          # Plugin manifest (name, version, description)
  skills/              # Skills (noun-phrase names, e.g., "docs-management")
    <skill-name>/
      SKILL.md         # Skill definition with YAML frontmatter
      references/      # Supporting docs loaded on-demand
      scripts/         # Python/Bash automation scripts
  commands/            # Slash commands (verb-phrase names, e.g., "scrape-docs")
  agents/              # Subagent definitions
  hooks/               # Hook configurations
```

### Documentation Management Pattern

The `docs-management` and `gemini-cli-docs` skills manage scraped official documentation with search indexes. **Always invoke the skill** to search docs - never read index.yaml directly. Skills handle search ranking, keyword extraction, and subsection loading.

### Key Plugins

| Plugin | Purpose |
| ------ | ------- |
| claude-ecosystem | Claude Code docs, skills (docs-management, hook-management, memory-management), hooks |
| google-ecosystem | Gemini CLI docs (gemini-cli-docs), planning agents |
| code-quality | Code review, markdown linting, debugging |
| tactical-agentic-coding | ADW workflows, prompt engineering, agent design |
| git | Git operations (config, GPG signing, hooks, GitHub issues) |

## Conventions

- Skills: noun-phrase names (`hook-management`)
- Commands: verb-phrase names (`scrape-docs`)
- Skills use `allowed-tools`, agents use `tools` in frontmatter
- YAML frontmatter required for SKILL.md files (name, description, allowed-tools)
- References loaded progressively (just-in-time) to optimize tokens

## Detailed Documentation

For comprehensive guidance on working with this repository, see:

**Always Loaded (Core Principles):**

- **Command/Skill Execution Protocol** @.claude/memory/command-skill-protocol.md (~3,215 tokens) - CRITICAL: Prevents context collapse when executing commands/skills
- **Operational Rules** @.claude/memory/operational-rules.md (~2,400 tokens) - Core operational guidance (temp files, error handling, workflow management)
- **Claude Code ecosystem reference** @.claude/memory/claude-code-ecosystem.md (~2,300 tokens) - Enforcement layers, skills table, and delegation pattern for Claude Code documentation

**Context-Dependent (Load When Needed):**

- **Path Conventions** `.claude/memory/path-conventions.md` (~2,105 tokens) - Path resolution, absolute paths, path doubling, script execution
- **Script Automation** `.claude/memory/script-automation.md` (~2,180 tokens) - PowerShell, Python, Bash, script creation, automation
- **Agent Usage Patterns** `.claude/memory/agent-usage-patterns.md` (~3,370 tokens) - Parallelization, subagents, model selection, agent communication
- **Performance Quick Start** `.claude/memory/performance-quick-start.md` (~1,925 tokens) - Performance, speed, latency, optimization
- **Workflows** `.claude/memory/workflows.md` (~4,400 tokens) - TDD, visual iteration, headless mode, multi-Claude, plan mode
- **Behavioral Principles** `.claude/memory/behavioral-principles.md` (~2,250 tokens) - Communication, autonomy, limitations, transparency
- **Natural Language Prompting** `.claude/memory/natural-language-guidance.md` (~700 tokens) - Natural language, intent, agentic instructions
- **Anti-Patterns & Design Decisions** `.claude/memory/anti-patterns.md` (~1,880 tokens) - @-file bloat, slash command over-engineering, hook timing
- **Tool Optimization** `.claude/memory/tool-optimization.md` (~2,200 tokens) - Tool design, tool selection, namespacing, error messages
- **Context Engineering** `.claude/memory/context-engineering.md` (~4,390 tokens) - Context window, /compact, /clear, context rot, token budget
- **Hook Timing Philosophy** `.claude/memory/hook-timing-philosophy.md` (~2,050 tokens) - PreToolUse, PostToolUse, block-at-submit, auto-fix
- **Testing Principles** `.claude/memory/testing-principles.md` (~17,300 tokens) - FIRST principles, test pyramid, AAA pattern, mocking
- **Clean Code Guidelines** `.claude/memory/clean-code-guidelines.md` (~9,800 tokens) - SOLID, code smells, refactoring, naming conventions
- **Engineering Best Practices** `.claude/memory/engineering-best-practices.md` (~1,225 tokens) - Concurrency, caching, error handling, resilience
- **Anti-Duplication Enforcement** `.claude/memory/anti-duplication-enforcement.md` (~2,000 tokens) - Duplicate content, consolidation, single source of truth
- **Model Identification** `.claude/memory/model-identification.md` (~710 tokens) - Model identity, Opus, Sonnet, Haiku, audit metadata
- **Prompting Style Guide** `.claude/memory/prompting-style-guide.md` (~3,090 tokens) - Tone, prompting, Claude 4.5 best practices
- **Standard Operating Procedures** `.claude/memory/standard-operating-procedures.md` (~5,820 tokens) - SOP, best practices, agent execution
- **Claude Code Antipatterns** `.claude/memory/claude-code-antipatterns.md` (~16,780 tokens) - Antipatterns, bad practices, Opus 4.5 issues
- **Session Configuration** `.claude/memory/session-configuration.md` (~1,930 tokens) - HTTPS_PROXY, timeout, session management
- **GitHub Actions Patterns** `.claude/memory/github-actions-patterns.md` (~2,195 tokens) - GitHub Actions, CI/CD, PR automation
- **MCP Usage Patterns** `.claude/memory/mcp-usage-patterns.md` (~650 tokens) - MCP, microsoft-learn, context7, ref, perplexity
- **Plugin Dev Mode** `.claude/memory/plugin-dev-mode.md` (~1,200 tokens) - Dev mode env vars, installed vs local plugin, scraping to dev repo

**Claude Code Ecosystem:**

- **Claude Code Topics Index** `.claude/memory/claude-code-topics-index.md` (~3,420 tokens) - Hooks, memory, skills, subagents, MCP, plugins, settings, SDK

**Last Updated:** 2025-12-06
