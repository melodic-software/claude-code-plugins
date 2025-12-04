# Lesson 1 Analysis: Hello Agentic Coding - Become the Engineer They Can't Replace

## Content Summary

### Core Tactic

**Stop Coding** - Your hands and mind are no longer the best tools for writing code. Language models wrapped in the right agent architecture, running on supercomputers are vastly superior coders. Use the best tool for the job.

### Key Frameworks

- **The Big Three (AI Coding)**: Context, Model, Prompt
- **The Core Four (Agentic Coding)**: Context, Model, Prompt, **Tools**
- **Phase 1 vs Phase 2**: AI Coding (generate code) vs Agentic Coding (build systems that build systems)

### Phase 2 Role Definition

The irreplaceable engineer in phase two:

- Allocates engineering cycles to **planning**, **reviewing**, and **creating closed loop structures**
- Transforms codebases into **self-operating machines**
- Becomes a **commander of compute**
- Builds **systems that build systems**

### Implementation Patterns from Repo (tac-1)

1. **AI Coding Prompt** - Simple, single-action code generation:

   ```markdown
   CREATE main_aic.py:
       print goodbye ai coding
   ```

2. **Agentic Coding Prompt** - Multi-step workflow with tool calls:

   ```markdown
   RUN:
       checkout a new/existing "demo-agentic-coding" git branch
   CREATE main_tac.py:
       print "hello agentic coding"
       print a concise explanation of the definition of ai agents
   RUN:
       uv run main_aic.py
       uv run main_tac.py
       git add .
       git commit -m "Demo agentic coding capabilities"
   ```

3. **Programmable Agentic Coding** - Running Claude Code from scripts:
   - Shell: `claude -p "$PROMPT_CONTENT"`
   - Python: `subprocess.run(["claude", "-p", prompt_content])`
   - TypeScript (Bun): `$\`claude -p ${promptContent}\``

4. **Permission Configuration** - Scoped tool access via `.claude/settings.json`:

   ```json
   {
     "permissions": {
       "allow": [
         "Read", "Write", "Edit",
         "Bash(uv run:*)",
         "Bash(git checkout:*)",
         "Bash(git branch:*)",
         "Bash(git add:*)",
         "Bash(git commit:*)",
         "WebSearch"
       ]
     }
   }
   ```

### Anti-Patterns Identified

- **Vibe Coding**: Typing code by hand when agents can do it better
- **Phase 1 Thinking**: Only generating code, not building systems
- **Tool Attachment**: Getting stuck on any one tool instead of transferring tactics

### Metrics/KPIs

- **Leverage Ratio**: 10 minutes of your work = 60+ minutes of another engineer's work
- **Self-Operation**: Degree to which codebase runs itself

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| None for Lesson 1 | Foundational philosophy, no specific workflow | N/A |

### Subagents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| None for Lesson 1 | Foundational philosophy | N/A |

### Commands

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| None for Lesson 1 | No specific command pattern | N/A |

### Memory Files

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `core-four-principles.md` | Define the Core Four (Context, Model, Prompt, Tools) | Always - foundational concept |
| `agentic-coding-mindset.md` | Phase 2 mindset: stop coding, build systems that build systems | Always - mindset guidance |
| `programmable-claude-patterns.md` | Patterns for running Claude Code programmatically | When building automation |

## Key Insights for Plugin Development

### Lesson 1 is Foundational Philosophy

This lesson establishes the **mindset** rather than specific techniques. The key takeaways to encode:

1. **Stop coding** - Let agents handle implementation
2. **Core Four** - Always consider Context, Model, Prompt, Tools
3. **Programmable Claude Code** - Can be invoked from any scripting language
4. **Permission scoping** - Use `.claude/settings.json` for controlled tool access
5. **Phase 2 role** - Planning, reviewing, closed-loop structures

### Recommended Plugin Components

1. **Memory File: `tac-mindset.md`**
   - Core philosophy of tactical agentic coding
   - The Core Four framework
   - Phase 1 vs Phase 2 distinction
   - Commander of compute mindset

2. **Memory File: `programmable-patterns.md`**
   - Examples of running Claude Code from shell/Python/TypeScript
   - Permission configuration patterns

### Not Recommended

- **Skills/Subagents/Commands**: Lesson 1 is too foundational for specific tooling
- These should wait until we have actionable workflows (Lessons 3-7)

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read links.md (external resources)
- [x] Read captions.txt (full transcript)
- [x] Explored tac-1 repository
- [x] Read README.md
- [x] Read .claude/settings.json
- [x] Read programmable/*.py,*.sh, *.ts
- [x] Read programmable/prompt.md
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Sets up for Lesson 2**: Leverage points (where to apply the Core Four)
- **Sets up for Lesson 3**: Planning and templates (how to structure agent work)
- **Sets up for Lesson 4**: AFK agents (closed loop structures)

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
