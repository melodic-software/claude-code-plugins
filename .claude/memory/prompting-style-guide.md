# Prompting Style Guide

This guide provides prompting best practices for Claude 4.5 models (Opus 4.5, Sonnet 4.5, Haiku 4.5), derived from official Anthropic documentation.

## Core Principle: Dial Back Aggressive Language

Claude 4.5 models are more responsive to system prompts than previous generations. Prompts designed to reduce undertriggering on tools or skills may now cause **overtriggering**.

**The fix**: Use normal, directive language instead of aggressive emphasis.

| Instead of | Use |
| ---------- | --- |
| "CRITICAL: You MUST use this tool when..." | "Use this tool when..." |
| "NEVER skip this step" | "Complete this step before proceeding" |
| "ALWAYS verify first" | "Verify first, then proceed" |
| "MANDATORY: Do X" | "Do X" |
| "WARNING: Failure to..." | "To ensure success, ..." |

## Tone Calibration

### Directive vs Suggestive Language

Claude 4.5 models follow instructions precisely. Be explicit about desired behavior without aggressive emphasis.

**Directive (preferred)**:

```text
Use tool X when condition Y is met. Answer directly otherwise.
```

**Aggressive (avoid)**:

```text
You MUST ALWAYS use tool X whenever condition Y is met. NEVER answer without using the tool first.
```

### Treat Claude as a Competent Professional

Frame instructions as you would for a skilled colleague - clear, direct, and respectful. Avoid patterns that create anxiety or over-caution.

**Professional**:

```text
Read the relevant code files before proposing changes. This ensures your suggestions align with existing patterns.
```

**Anxiety-inducing (avoid)**:

```text
CRITICAL: You MUST read ALL relevant code files BEFORE proposing ANY changes. FAILURE to do so will result in CATASTROPHIC errors.
```

## Positive Framing

Tell Claude what to do, not what to avoid. Positive framing produces better results than negative constraints.

| Negative (avoid) | Positive (preferred) |
| ---------------- | -------------------- |
| "Do not use markdown" | "Write in flowing prose paragraphs" |
| "Don't hardcode paths" | "Use dynamic path resolution" |
| "Never ignore errors" | "Report all errors with context" |
| "Don't skip verification" | "Verify each step before proceeding" |
| "Avoid abbreviations" | "Write out terms fully for clarity" |

## Context and Motivation

Provide context for rules so Claude can generalize the principle, not just follow blindly.

**Without context (less effective)**:

```text
Never use ellipses.
```

**With context (more effective)**:

```text
Avoid ellipses because your response will be read aloud by a text-to-speech engine that cannot pronounce them correctly.
```

Claude will understand the underlying goal (clarity for TTS) and apply it broadly to similar situations.

## Action-Oriented Instructions

Claude 4.5 follows instructions precisely. If you want action, be explicit.

**Suggestion (Claude will only suggest)**:

```text
Can you suggest some changes to improve this function?
```

**Action (Claude will implement)**:

```text
Change this function to improve its performance.
```

Or:

```text
Implement these improvements to the authentication flow.
```

## Exploration Before Solutions

Claude Opus 4.5 can be conservative when exploring code. Encourage thorough exploration before proposing changes.

**Effective exploration prompt**:

```text
Read and understand relevant files before proposing code edits. Do not speculate about code you have not inspected. If referencing a specific file, open and review it before explaining or proposing fixes. Thoroughly review the style, conventions, and abstractions of the codebase before implementing new features.
```

## Verbosity and Summarization

Claude 4.5 models tend toward efficiency and may skip summaries after tool use. If you want visibility into reasoning:

```text
After completing a task that involves tool use, provide a concise summary of the work done.
```

For research tasks requiring transparency:

```text
After each major step, provide a brief summary of what you found and what you did.
```

## Thinking Word Sensitivity

When extended thinking is disabled, Claude Opus 4.5 is particularly sensitive to the word "think". Use alternative words:

| Instead of | Use |
| ---------- | --- |
| "Think step by step" | "Consider each step carefully" |
| "Think about..." | "Evaluate..." or "Consider..." |
| "Think through..." | "Work through..." or "Analyze..." |

## Extended Thinking in Claude Code

Claude Code supports thinking keywords that trigger extended thinking with specific budget allocations:

| Keyword | Budget Tokens | Use Case |
| ------- | ------------- | -------- |
| `think` | ~4,000 | Basic reasoning tasks |
| `think hard` / `megathink` | ~10,000 | Complex problems |
| `think harder` / `ultrathink` | ~31,999 | Most complex challenges |

**Detection phrases for ultrathink level:**

- "think harder", "think intensely", "think longer"
- "think really hard", "think super hard", "think very hard"
- "ultrathink"

**Best practices for extended thinking:**

1. **Use general instructions first** - High-level guidance often works better than step-by-step prescriptions:

   ```text
   Consider this problem thoroughly and in great detail.
   Explore multiple approaches and show your complete reasoning.
   ```

2. **Have Claude verify its work:**

   ```text
   Before finalizing, verify your solution with test cases and fix any issues you find.
   ```

3. **For complex multi-step tasks:**

   ```text
   Break this down systematically. Track your progress and confidence levels.
   Update your approach based on what you learn at each step.
   ```

**Note:** Thinking keywords only work in Claude Code (the terminal tool), not in Claude's web interface or standard API. For API usage, use the `thinking` parameter explicitly.

## Parallel Tool Execution

Claude 4.5 models excel at parallel tool execution. Sonnet 4.5 is particularly aggressive with parallelization. This is steerable:

**Maximum parallelization**:

```text
When calling multiple tools with no dependencies between them, make all independent calls in parallel. Maximize parallel tool use for speed and efficiency. Only run sequentially when calls depend on previous results.
```

**Explicit parallel tool prompt** (for system prompts):

```text
If you intend to call multiple tools and there are no dependencies between the
tool calls, make all of the independent tool calls in parallel. Prioritize calling
tools simultaneously whenever the actions can be done in parallel rather than
sequentially. For example, when reading 3 files, run 3 tool calls in parallel to
read all 3 files into context at the same time. Maximize use of parallel tool
calls where possible to increase speed and efficiency. However, if some tool calls
depend on previous calls to inform dependent values like the parameters, do NOT
call these tools in parallel and instead call them sequentially. Never use
placeholders or guess missing parameters in tool calls.
```

**Reduced parallelization**:

```text
Execute operations sequentially with brief pauses between each step to ensure stability.
```

## Overengineering Prevention

Claude Opus 4.5 tends to over-engineer by creating extra files, unnecessary abstractions, or unneeded flexibility. Add explicit constraints:

```text
Keep solutions minimal and focused. Only make changes that are directly requested or clearly necessary.

Avoid:
- Adding features beyond what was asked
- Refactoring surrounding code during bug fixes
- Creating helpers or utilities for one-time operations
- Adding error handling for scenarios that cannot happen
- Designing for hypothetical future requirements

The right amount of complexity is the minimum needed for the current task.
```

## Frontend Design Aesthetics

Without guidance, models default to generic patterns ("AI slop" aesthetic). For distinctive, creative frontends:

```text
Create distinctive frontends that surprise and delight. Avoid generic AI-generated aesthetics.

Focus on:
- **Typography**: Choose beautiful, unique fonts. Avoid generic fonts like Arial and Inter.
- **Color & Theme**: Commit to a cohesive aesthetic. Dominant colors with sharp accents outperform timid, evenly-distributed palettes.
- **Motion**: Use animations for effects and micro-interactions. One well-orchestrated page load with staggered reveals creates more delight than scattered micro-interactions.
- **Backgrounds**: Create atmosphere and depth rather than defaulting to solid colors.

Avoid:
- Overused font families (Inter, Roboto, Arial)
- Cliched color schemes (purple gradients on white backgrounds)
- Predictable layouts and component patterns
- Cookie-cutter design lacking context-specific character

Vary between light and dark themes, different fonts, different aesthetics. Think outside the box.
```

## Formatting Control

For output format control:

1. **Tell Claude what to do** instead of what not to do
2. **Use XML format indicators** for structure: "Write sections in \<flowing_prose\> tags"
3. **Match prompt style to desired output** - removing markdown from your prompt reduces markdown in output
4. **Be explicit about preferences**:

```text
When writing reports or long-form content, use clear flowing prose with complete paragraphs. Reserve markdown for inline code and code blocks only. Avoid bullet lists unless presenting truly discrete items or the user explicitly requests a list.
```

## Subagent Orchestration

Claude 4.5 models recognize when tasks benefit from delegation and do so proactively. To adjust:

**Conservative subagent usage**:

```text
Only delegate to subagents when the task clearly benefits from a separate agent with a new context window.
```

## Long-Horizon Agent Tasks

For extended autonomous work sessions, Claude Opus 4.5 can work for hours with proper context management.

**Enable persistence:**

```text
Your context window will be automatically compacted as it approaches its limit, allowing you to continue working indefinitely. Do not stop tasks early due to token budget concerns. Save your current progress to memory before context window refreshes. Be as persistent and autonomous as possible and complete tasks fully.
```

**State management patterns:**

- Use structured formats (JSON) for test results and task status
- Use unstructured text for progress notes
- Use git for long-term state tracking
- Create setup scripts for graceful recovery after context refresh

## Research and Information Gathering

Opus 4.5 excels at agentic search. For optimal research:

```text
Search for this information systematically. As you gather data, develop competing hypotheses. Track your confidence levels in progress notes. Regularly self-critique your approach and update your research plan based on findings.
```

## Four Key Context Engineering Strategies

From the latest Anthropic guidance on context management:

| Strategy | Purpose |
| -------- | ------- |
| Writing | Store and structure external memory |
| Selecting | Retrieve only the most relevant information for each task |
| Compressing | Summarize or trim context to manage token consumption |
| Isolating | Create compartmentalized workflows to avoid confusion |

These strategies help manage context effectively across long-running tasks and multi-agent workflows.

## Summary

The key shift for Claude 4.5:

- **Less aggressive language** - normal directives work better than emphasized commands
- **Positive framing** - say what to do, not what to avoid
- **Explicit action** - be clear when you want implementation vs. suggestions
- **Contextual rules** - explain why rules exist so Claude can generalize
- **Exploration first** - encourage reading code before proposing changes
- **Extended thinking** - use thinking keywords for complex reasoning (think, think hard, ultrathink)
- **Long-horizon persistence** - can work autonomously for hours with proper context management
- **Creative design** - guide away from generic patterns toward distinctive choices

These principles help Claude 4.5 deliver better results without triggering over-cautious or over-eager behavior.

---

**Model**: Claude Opus 4.5 (`claude-opus-4-5-20251101`)

**Source**: Official Anthropic documentation at `docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices`

**Last Updated**: 2025-11-30
