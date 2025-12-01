# CLAUDE.md

See @README for project overview and installation.

## Critical Rules

- **NEVER read `index.yaml` directly** - use `manage_index.py` scripts
- **NEVER chain `cd &&` in PowerShell** - causes path doubling
- **Use `MSYS_NO_PATHCONV=1`** in Git Bash
- **Use Python 3.12** for spaCy operations
- **Plugin dev mode required** - When modifying plugin scripts, set env vars to use local code instead of installed plugin. See `.claude/memory/plugin-dev-mode.md`

## Quick Reference

- **Skills First**: Before using tools, check if a matching skill exists and invoke it. Once loaded, follow the skill's complete workflow - skills are workflows to execute, not reference docs to bypass. When a skill instructs you to run a command, execute it immediately rather than stating assumed results. Skills exist because assumptions are unreliable; verification through execution ensures accuracy.
  - **Skill Execution Fidelity**: When a skill provides execution instructions (bash commands, script patterns, workflow steps): (1) Read the skill's workflow section completely before executing tools, (2) Execute exactly as instructed without substituting alternative approaches, (3) Verify your execution matches the skill's pattern before proceeding, (4) If you deviate, stop and correct immediately.
  - **Pre-Execution Skill Verification**: Before executing skill-provided commands or scripts: (1) Locate the execution pattern in SKILL.md (search for "Run", "Execute", "Do NOT"), (2) Read the full instruction (foreground/background, polling/streaming, etc.), (3) Verify your planned tool call matches the pattern exactly, (4) If any mismatch, re-read skill instructions.
- **Proactive Delegation**: Before starting multi-step or multi-item tasks, evaluate for parallel delegation:
  1. **Identify independent items**: Creating 4 files? Analyzing 5 components? Updating 3 platforms? Each is a candidate for delegation
  2. **Parallelize when independent**: If items have no dependencies, run up to 5 subagents simultaneously (90% speedup)
  3. **Preserve main context**: Delegate research/exploration to keep main agent context clean for user interaction
  4. **Sequential requires justification**: Default to parallel delegation; use sequential only when tasks have dependencies
  5. **Model selection**: Haiku for simple/search tasks (2-3x faster), Sonnet for complex reasoning, Opus for critical decisions
  - **Recognition patterns (parallelize these)**:
    - "Create/update N things" -> N parallel subagents (max 5 concurrent, batch if more)
    - "Update across platforms" -> 1 subagent per platform
    - "Research/explore X" -> Explore subagent (preserves main context)
    - "Analyze multiple concerns" -> 1 subagent per concern
- **Claude Code Documentation Requirement**: For anything related to Claude, Claude Code, or Claude Code ecosystem features (hooks, memory, skills, subagents, commands, MCP, plugins, settings, model config, workflows, SDK, etc.):
  1. Use the `docs-management` skill to access official canonical documentation first
  2. Base responses on official documentation rather than assumptions or memory
  3. Drive all changes/modifications from official canonical documentation
  4. If official documentation is unclear or missing, state this explicitly rather than guessing
  5. See @.claude/memory/claude-code-ecosystem.md for comprehensive topic index and delegation instructions
- **Zero Complacency - Report All Errors/Warnings**: When you encounter errors, warnings, import failures, deprecation notices, or any system feedback indicating something is wrong:
  1. Stop and do not continue or report success when errors are present
  2. Report the error/warning explicitly to the user with full context
  3. If you are confident of the fix and it requires low effort (not medium+ refactor): Auto-fix it immediately and verify the fix worked
  4. If unsure or medium+ effort required: Report to user and propose solution rather than guessing
  5. Verify actual success before claiming it - imports working, tests passing, no warnings
- **Current date awareness**: Automatically injected at session start via `inject-current-date` hook. For time-sensitive operations requiring the latest time, execute `date -u` directly
- **Verify model identity**: Before reporting which model you are (especially in audits/skill metadata), check your system context where model info is provided. See `.claude/memory/model-identification.md` for comprehensive guidance
- **MCP Server Usage**: Use MCP servers proactively before writing code/docs. Microsoft tech -> `microsoft-learn`, libraries -> `context7`+`ref`, general -> `perplexity`+`firecrawl`. See `.claude/memory/mcp-usage-patterns.md` for detailed selection guide
- **Path doubling prevention**: Detect and prevent path doubling errors proactively. When executing commands with `cd` and `&&` in PowerShell, or when using relative paths in scripts, resolve paths absolutely from repo root before operations. See `.claude/memory/path-conventions.md` for detailed guidance
- **Exploration before solutions**: Read and understand relevant code before proposing changes. Verify existing patterns before creating new ones. Do not speculate about code you have not inspected
- **Research before planning**: Conduct comprehensive research to understand all components, current state, and desired future state before proposing solutions
- **Use agent efficiency**: Offload complex research/exploration to Task agents when appropriate; use `.claude/temp/` for agent communication via .md files
- **Performance optimization**: Use parallelization (3-5 agents = 90% speedup), Haiku model for simple tasks (2-3x faster), focused queries (not exhaustive searches). See @.claude/memory/performance-quick-start.md for comprehensive guide
- **Prefer script-based automation**: Prefer scripts over manual file generation/manipulation when feasible - saves tokens, faster execution, more deterministic output. See @.claude/memory/operational-rules.md for detailed guidance
- **Use temporary workspace**: Use `.claude/temp/YYYY-MM-DD_HHmmss-{agent-type}-{topic}.md` for scratch files because this location is gitignored by default. Timestamp in UTC
- **Clean up temporary files**: Remove temporary test files, scripts, and artifacts that are not gitignored before completing any task. Run `git status` before completion to verify no unintended files remain
- **UTC timestamps for all persisted data**: Default to UTC for timestamps in ISO-8601 format. Store all persisted data in UTC - convert to local time only for display purposes
- **Command/Skill execution**: When executing commands that invoke skills/agents, maintain dual-level awareness and verify ALL steps before reporting completion (see @.claude/memory/command-skill-protocol.md)
- **Use natural language prompting**: Use natural language describing intent for agentic instructions (commands, skills, agents) - see @.claude/memory/natural-language-guidance.md
- **ASCII punctuation only**: Use straight ASCII punctuation in all docs, prompts, and responses because smart/curly quotes cause encoding issues in scripts and cross-platform compatibility problems
- **UTF-8 encoding for all files**: Use UTF-8 encoding for all files. Preserve emojis and Unicode characters. When creating Python scripts, explicitly set UTF-8 encoding for stdin/stdout/stderr
- **Skill encapsulation (global rule)**: Outside a skill, the ONLY thing you may reference is the **skill name** plus **natural language behavior/context**. Commands, docs, and other skills must not mention internal scripts, file paths, or CLI flags
- **Context engineering**: Treat context as a finite resource with diminishing returns. Find the smallest set of high-signal tokens that maximize desired outcomes. See `.claude/memory/context-engineering.md`
- **Progressive disclosure**: Use just-in-time context strategies - discover and load information on-demand rather than pre-processing all data upfront
- **Start simple, add complexity only when needed**: Find the simplest solution possible, only increase complexity when demonstrably needed
- **Overengineering prevention**: Keep solutions minimal and focused. Only make changes directly requested or clearly necessary
- **Perfect is the enemy of good**: Ship working solutions and refine iteratively. Recognize when "good enough" serves users better than pursuing theoretical ideals
- **Course correction**: Course correct early and often. Make a plan before coding, and don't code until the plan is confirmed. Press Escape to interrupt during any phase. Use `/clear` frequently between tasks to reset context window
- **Extended thinking**: Use "think" keywords for deeper evaluation: "think" < "think hard" < "think harder" < "ultrathink" (each level allocates progressively more thinking budget)
- **Claude Code ecosystem**: For all Claude Code topics (hooks, memory, skills, subagents, MCP, plugins, settings, model config, workflows, SDK, etc.), see @.claude/memory/claude-code-ecosystem.md for comprehensive topic index and delegation instructions to docs-management skill
- **Tool selection and usage**: When tools are available, select tools with clear distinct purposes. Prefer error-proof tools (e.g., those requiring absolute paths vs relative). Use tools that return meaningful context
- **Context awareness and persistence**: When working in environments with automatic context compaction, do not stop tasks early due to token budget concerns. Save current progress and state to memory before context window refreshes. Continue working persistently and autonomously
- **Communication style**: Provide fact-based progress reports rather than verbose summaries. Be concise, direct, and grounded in what has actually been accomplished
- **Test preservation**: Preserve tests because they verify correctness. If tests appear incorrect or the task unreasonable, inform the user rather than working around them
- **Test-driven and behavior-driven development (TDD/BDD)**: When adding or changing non-trivial behavior, prefer TDD or BDD where feasible
- **Security-first thinking**: Never expose or log sensitive data. Validate and sanitize all inputs. Default to least privilege
- **Consistency as a first-class rule**: Use the same patterns, structures, and naming everywhere. Do not introduce a new approach when an existing one can be extended
- **Pattern-first changes**: Before adding docs, workflows, or structures, look for an existing pattern in this repo and align to it
- **Anti-Duplication**: Ensure every piece of information exists in exactly one authoritative location. Before creating content, search for existing content on the topic. See `.claude/memory/anti-duplication-enforcement.md`
- **Single source of truth**: Avoid duplicating guidance. Prefer one canonical location and link to it from other docs
- **DRY and deduplication**: Minimize duplicated variables, magic strings, magic numbers, and repeated code
- **Law of Demeter (principle of least knowledge)**: Minimize coupling by talking only to immediate friends. Avoid brittle chains
- **Best tool for the job**: Choose languages, libraries, and techniques that keep the solution simple, maintainable, and testable
- **AI-friendly structure**: Use predictable sections and headings (Overview, Prerequisites, Installation, Configuration, Verification, Troubleshooting) so LLMs can reliably locate and reuse information
- **Naming and terminology alignment**: Use consistent terminology for the same concepts across all docs
- **Minimal, focused edits**: Make small, intentional changes that preserve existing formatting and structure
- **Cross-platform, test-first mindset**: Treat Windows, macOS, and Linux as first-class. Consider platform differences up front
- **No partial handoffs**: Do not end a task with "you finish this" or leave failing tests for the user
- **Implementation integrity**: Do things correctly or do not do them at all. Avoid workarounds, hacks, or temporary fixes. Fix failing tests by fixing the code or tests with clear rationale

## Documentation

For Claude Code topics, invoke the `docs-management` skill or use:

```bash
python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py search <keywords>
```

For Gemini CLI topics, invoke the `gemini-cli-docs` skill or use:

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/core/find_docs.py search <keywords>
```

## Conventions

- Skills: noun-phrase names (`hook-management`)
- Commands: verb-phrase names (`scrape-docs`)
- Skills use `allowed-tools`, agents use `tools` in frontmatter

## Detailed Documentation

For comprehensive guidance on working with this repository, see:

**Always Loaded (Core Principles):**

- **Command/Skill Execution Protocol** @.claude/memory/command-skill-protocol.md (~3,215 tokens) - CRITICAL: Prevents context collapse when executing commands/skills
- **Operational Rules** @.claude/memory/operational-rules.md (~2,400 tokens) - Core operational guidance (temp files, error handling, workflow management)
- **Claude Code ecosystem reference** @.claude/memory/claude-code-ecosystem.md (~1,025 tokens) - Enforcement layers, skills table, and delegation pattern for Claude Code documentation

**Context-Dependent (Load When Needed):**

- **Path Conventions** `.claude/memory/path-conventions.md` (~2,105 tokens) - Path resolution, absolute paths, path doubling, script execution
- **Script Automation** `.claude/memory/script-automation.md` (~2,180 tokens) - PowerShell, Python, Bash, script creation, automation
- **Agent Usage Patterns** `.claude/memory/agent-usage-patterns.md` (~3,370 tokens) - Parallelization, subagents, model selection, agent communication
- **Performance Quick Start** `.claude/memory/performance-quick-start.md` (~1,925 tokens) - Performance, speed, latency, optimization
- **Workflows** `.claude/memory/workflows.md` (~4,400 tokens) - TDD, visual iteration, headless mode, multi-Claude, plan mode
- **Behavioral Principles** `.claude/memory/behavioral-principles.md` (~2,250 tokens) - Communication, autonomy, limitations, transparency
- **Natural Language Prompting** `.claude/memory/natural-language-guidance.md` (~700 tokens) - Natural language, intent, agentic instructions
- **Anti-Patterns & Design Decisions** `.claude/memory/anti-patterns.md` (~1,880 tokens) - @-file bloat, slash command over-engineering, hook timing
- **Tool Optimization** `.claude/memory/tool-optimization.md` (~2,245 tokens) - Tool design, tool selection, namespacing, error messages
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

**Last Updated:** 2025-12-01
