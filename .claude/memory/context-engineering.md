# Context Engineering Principles

**Token Budget:** ~4,390 tokens | **Load Type:** Context-dependent (load for context management guidance)

This document contains principles for effectively engineering context for AI agents, extracted from Anthropic's engineering research on context management and optimization.

**Source:** Use docs-management skill to find "effective-context-engineering-for-ai-agents" documentation

## Core Principle

Context is a finite resource with diminishing marginal returns. Good context engineering means finding the **smallest possible set of high-signal tokens** that maximize the likelihood of your desired outcome.

## Why Context Engineering Matters

### Attention Budget Constraints

LLMs have limited "attention budget" - as context length increases:

- Token position understanding gets stretched thin
- Ability to capture pairwise relationships degrades
- Performance gradient emerges (not a hard cliff, but measurable reduction)

**Key insight:** Models have less experience with, and fewer specialized parameters for, context-wide dependencies compared to shorter sequences.

### Context Rot

Studies show "context rot": as the number of tokens in context increases, the model's ability to accurately recall information from that context decreases. This characteristic emerges across all models, though some exhibit more gentle degradation than others.

## System Prompt Engineering

### Right "Altitude"

System prompts should be clear and use simple, direct language at the **right altitude** - the Goldilocks zone between:

**Too specific (brittle):**

- Hardcoding complex, brittle logic in prompts
- Creates fragility and maintenance complexity
- Forces exact agentic behavior with if-else structures

**Too vague (unclear):**

- Overly general, high-level guidance
- Fails to give concrete signals for desired outputs
- Falsely assumes shared context

**Optimal (balanced):**

- Specific enough to guide behavior effectively
- Flexible enough to provide strong heuristics
- Clear without being prescriptive

### Organization Structure

Organize prompts into distinct sections using:

- XML tags (e.g., `<background_information>`, `<instructions>`, `## Tool guidance`, `## Output description`)
- Markdown headers
- Clear section boundaries

**Note:** Exact formatting becomes less important as models become more capable, but structure still helps.

### Minimal Set Principle

Strive for the minimal set of information that fully outlines expected behavior. **Note:** Minimal does not necessarily mean short - you still need sufficient information upfront to ensure adherence to desired behavior.

**Approach:**

1. Start with minimal prompt using best available model
2. Test performance on your task
3. Add clear instructions and examples based on observed failure modes
4. Iterate to improve precision while maintaining clarity

## Tool Design for Context Efficiency

Tools define the contract between agents and their information/action space. They must promote efficiency:

### Token-Efficient Tool Responses

- Return only high-signal information
- Use pagination, filtering, truncation
- Encourage efficient agent behaviors (e.g., targeted searches vs broad queries)

### Minimal Overlap

- Tools should have minimal overlap in functionality
- Bloated tool sets create ambiguous decision points
- If humans can't definitively say which tool to use, agents can't either

**Principle:** Curate a minimal viable set of tools - this leads to more reliable maintenance and context pruning over long interactions.

## Examples and Few-Shot Prompting

### Quality Over Quantity

**Don't:** Stuff a laundry list of edge cases into prompts attempting to articulate every possible rule.

**Do:** Curate a set of diverse, canonical examples that effectively portray expected behavior.

**Key insight:** For LLMs, examples are "pictures worth a thousand words." A few well-chosen examples communicate more than exhaustive rule lists.

## Just-In-Time Context Strategies

### Progressive Disclosure Pattern

Rather than pre-processing all relevant data upfront, maintain lightweight identifiers:

- File paths
- Stored queries
- Web links
- Metadata references

Use these references to dynamically load data into context at runtime using tools.

**Benefit:** Agents can:

- Navigate and retrieve data autonomously
- Incrementally discover relevant context through exploration
- Assemble understanding layer by layer
- Maintain only what's necessary in working memory

### Hybrid Strategy

For many applications, effective agents employ a hybrid approach:

- **Pre-loading:** Some data retrieved up front for speed (e.g., CLAUDE.md files)
- **Just-in-time:** Additional exploration at agent's discretion (e.g., glob, grep, file reading)

**Example:** Claude Code drops CLAUDE.md into context upfront, while primitives like glob and grep enable just-in-time navigation. This bypasses stale indexing and complex syntax tree issues.

**Trade-off:** Runtime exploration is slower than pre-computed data, but provides more flexibility and avoids staleness.

## Long-Horizon Context Management

For tasks spanning extended time horizons (tens of minutes to hours), agents require specialized techniques:

### 1. Compaction

**What:** Summarize conversation nearing context window limit, then reinitiate with compressed summary.

**How:**

- Pass message history to model for summarization
- Preserve: architectural decisions, unresolved issues, implementation details
- Discard: redundant tool outputs, redundant messages
- Keep: five most recently accessed files for continuity

**Tuning approach:**

1. Start by maximizing recall (capture every relevant piece)
2. Iterate to improve precision (eliminate superfluous content)
3. Carefully tune prompt on complex agent traces

**Safest first step:** Clear tool results deep in message history once no longer needed (tool result clearing).

### 2. Structured Note-Taking

**What:** Agent regularly writes notes persisted outside context window, pulled back in later.

**Examples:**

- Claude Code creating to-do lists
- Custom agents maintaining NOTES.md files
- Tracking progress across complex tasks
- Maintaining critical context and dependencies

**Benefit:** Minimal overhead while providing persistent memory. Enables coherence across context resets for multi-hour tasks.

**Pattern:** Use structured formats (JSON) for state data, unstructured text for progress notes.

### 3. Sub-Agent Architectures

**What:** Specialized sub-agents handle focused tasks with clean context windows.

**How:**

- Main agent coordinates with high-level plan
- Sub-agents perform deep technical work or information gathering
- Each sub-agent can use tens of thousands of tokens
- Sub-agents return condensed summaries (1,000-2,000 tokens)

**Benefit:** Separation of concerns - detailed search context isolated within sub-agents, lead agent focuses on synthesis.

**Trade-off selection:**

- **Compaction:** Maintains conversational flow for extensive back-and-forth
- **Note-taking:** Excels for iterative development with clear milestones
- **Multi-agent:** Handles complex research/analysis where parallel exploration pays

## Claude 4.5 Platform Capabilities (September 2025)

Claude 4.5 models have native context awareness - they can track their remaining context window ("token budget") throughout a conversation.

### Context Editing

Automatically clears stale tool calls and results when approaching token limits. Preserves conversation flow while extending agent runtime.

**Performance gains:**

- Context editing + memory tool: 39% improvement on agentic search tasks
- Context editing alone: 29% improvement
- In 100-turn workflows: 84% reduction in token consumption

### Memory Tool

File-based system for storing information outside the context window that persists across conversations. Enables long-running agents to maintain state beyond single sessions.

### Inform Claude About Context Compaction

If using an agent harness that compacts context, add guidance like:

- Do not stop tasks early due to token budget concerns
- Save progress and state to memory before context window refreshes
- Continue working persistently and autonomously to completion

### Multi-Context Window Workflows

For tasks spanning multiple context windows:

| Strategy | Description |
| -------- | ----------- |
| Different first-window prompt | Use first context to set up framework (tests, scripts), iterate in subsequent windows |
| Structured test format | Create tests in structured format (e.g., tests.json) for better long-term iteration |
| Quality of life tools | Encourage setup scripts (e.g., init.sh) to prevent repeated work |
| Fresh start vs compacting | Claude 4.5 excels at discovering state from filesystem - sometimes better than compaction |
| Verification tools | Provide tools like Playwright MCP for testing UIs without human feedback |

### Starting Fresh Context Windows

Be prescriptive about how Claude should start:

- "Call pwd; you can only read and write files in this directory."
- "Review progress.txt, tests.json, and the git logs."
- "Run through a fundamental integration test before moving on."

### State Management Recommendations

| Data Type | Recommended Format |
| --------- | ------------------ |
| Structured info (test results, task status) | JSON or other structured formats |
| Progress notes | Unstructured freeform text |
| State tracking | Git - provides logs and restorable checkpoints |

Claude 4.5 performs especially well using git to track state across multiple sessions.

### Encourage Full Context Usage

For long tasks, encourage using the entire output context:

```text
This is a very long task, so it may be beneficial to plan out your work clearly.
It's encouraged to spend your entire output context working on the task - just
make sure you don't run out of context with significant uncommitted work. Continue
working systematically until you have completed this task.
```

## Context Retrieval Best Practices

### Metadata as Signals

Metadata of references provides efficient behavior refinement:

- **File hierarchies:** `test_utils.py` in `tests/` vs `src/core_logic/` implies different purpose
- **Naming conventions:** Hint at purpose and relationships
- **Timestamps:** Proxy for relevance
- **File sizes:** Suggest complexity

Let agents leverage these signals for intelligent navigation.

### Progressive Discovery

Enable agents to:

- Discover relevant context incrementally
- Use each interaction to inform next decision
- Assemble understanding layer by layer
- Self-manage context window to stay focused

This self-managed approach keeps agents focused on relevant subsets rather than drowning in exhaustive but potentially irrelevant information.

## Practical Guidelines

### For System Prompts

1. Find smallest high-signal token set
2. Use right "altitude" (balanced specificity)
3. Organize into distinct sections
4. Start minimal, add based on failure modes
5. Use diverse canonical examples (not exhaustive edge cases)

### For Tool Design

1. Return only high-signal information
2. Enable token-efficient strategies (pagination, filtering, truncation)
3. Minimize tool overlap
4. Design for agent affordances (not just wrapping APIs)

### For Long Tasks

1. Use compaction when approaching context limits
2. Implement structured note-taking for persistence
3. Consider sub-agent architectures for parallel exploration
4. Balance pre-loading vs just-in-time retrieval

### For Context Retrieval

1. Use lightweight references (paths, queries, links)
2. Enable progressive disclosure through exploration
3. Leverage metadata signals (hierarchy, naming, timestamps)
4. Consider hybrid strategies for optimal balance

## CLAUDE.md Philosophy

Practical guidance for maintaining an effective CLAUDE.md file.

### Start with Guardrails, Not a Manual

- Begin small, document based on what Claude gets wrong
- Add guidance reactively, not proactively
- Aim for guardrails that steer behavior, not comprehensive manuals
- If Claude handles something correctly without guidance, don't add guidance

**Anti-pattern:** Writing exhaustive documentation before observing any problems.

**Good pattern:** Notice Claude using `--force` instead of `--force-with-lease`, add specific guidance for that.

### The @-File Loading Trade-off

The `@path/to/file.md` import syntax embeds the ENTIRE file into context on every run.

**Problem:** Just mentioning a path without `@` means Claude often ignores it.

**Solution:** Use the "pitch" pattern - explain when and why to read the file:

```markdown
**Context-Dependent (Load When Needed):**
- **Path Conventions** `.claude/memory/path-conventions.md` (~2,800 tokens) -
  Load when working with paths, scripts, or debugging path doubling issues.
  Keywords: path resolution, absolute paths, path doubling, script execution
```

**Guidelines:**

- Reserve `@` syntax for truly essential, always-needed files (~10-15K tokens max)
- Use "pitch" pattern for conditional files with keywords
- Track token budgets explicitly

### Provide Alternatives to "Never"

Negative-only constraints cause the agent to get stuck:

| Bad                                    | Good                                                |
| -------------------------------------- | --------------------------------------------------- |
| "Never use --force"                    | "Never use --force, use --force-with-lease instead" |
| "Don't create backup files"            | "Use git for versioning instead of .bak files"      |
| "Avoid complex commands"               | "Wrap complex commands in scripts with clear APIs"  |

**Principle:** Always pair constraints with preferred approaches.

### CLAUDE.md as Forcing Function

If CLI commands require paragraphs of documentation to explain, that's a smell.

**Solution:**

1. Write a simple bash/script wrapper with clear API
2. Document the wrapper, not the complexity
3. Short CLAUDE.md forces better tooling

**Example:** Instead of documenting 10 flags for a complex command, create `./scripts/deploy.sh` with sensible defaults and document that.

## Context Reset Patterns

Strategies for managing context window when it fills up.

### Why /compact is Risky

The `/compact` command compresses context, but has significant risks:

- **Opaque algorithm** - you don't control what's preserved
- **Valuable context may be destroyed** - architectural decisions, key constraints
- **Not well-optimized** for all use cases
- **Silent loss** - you won't know what was dropped until problems emerge

### Preferred: /clear + Targeted Reload

1. `/clear` - Complete context reset
2. Reload specific context needed for next task
3. Custom `/catchup` command - re-read changed files in current git branch

**Benefits:**

- You control exactly what's in context
- Clean slate prevents context rot
- Targeted reload is more efficient than compacted mess

### Document & Clear (Complex Tasks)

For multi-session complex work spanning hours or days:

1. Have Claude dump plan and progress to a .md file in `.claude/temp/`
2. `/clear` the context
3. Start new session: "Read [file] and continue from where we left off"

**Why this works:**

- External memory survives context boundaries
- No loss of critical decisions or architectural choices
- Progress file can be version-controlled if needed
- Enables truly long-running tasks

### Context Reset Decision Tree

| Situation                 | Approach                |
| ------------------------- | ----------------------- |
| Simple task complete      | `/clear`                |
| Mid-task, context bloated | `/compact` (cautiously) |
| Complex multi-day work    | Document & Clear        |
| Terminal crashed          | `claude --continue`     |
| Resume old session        | `claude --resume`       |

### Session Management Commands

| Command             | Purpose                              |
| ------------------- | ------------------------------------ |
| `/clear`            | Complete context reset               |
| `/compact`          | Compress context (use cautiously)    |
| `claude --continue` | Reconnect after terminal issues      |
| `claude --resume`   | Resume previous session with context |

For comprehensive session management guidance, see `.claude/memory/session-configuration.md`.

## Summary

Context engineering is about thoughtfully curating what enters the model's limited attention budget at each step. The guiding principle: **find the smallest set of high-signal tokens that maximize the likelihood of your desired outcome.**

**Key practices:**

- System prompts at right "altitude" (balanced specificity)
- Minimal tool sets with clear purposes
- Canonical examples over exhaustive rules
- Just-in-time context loading with lightweight references
- Compaction for long conversations
- Structured note-taking for persistence
- Sub-agent architectures for complex tasks

**Source Documentation:**

- Use docs-management skill to find "effective-context-engineering-for-ai-agents" documentation
- Use docs-management skill to find "writing-tools-for-agents" documentation

---

**Last Updated:** 2025-12-06
