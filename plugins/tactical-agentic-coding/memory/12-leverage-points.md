# The 12 Leverage Points of Agentic Coding

Complete reference framework from TAC Lesson 002 by @IndyDevDan.

## Overview

Your agent is brilliant, but blind. With every new session, it starts as a blank instance - ephemeral, no context, no memories. If you want your agent to perform like you would, it needs your perspective: the information, tools, and resources you would use.

The 12 leverage points are where you can intervene to maximize your agent's success.

## Two Categories

### In-Agent (The Core Four)

Internal to the agent, always present. These are the four elements you control directly.

### Through-Agent (8 External Levers)

External interactions that multiply agent success. These are environmental factors that help your agent succeed.

---

## In-Agent Leverage Points (1-4)

### 1. Context

**What can your agent see?**

- CLAUDE.md files and memory
- Loaded files and conversation history
- MCP resources and external data

**High leverage**: Rich, relevant context enables informed decisions.

**Anti-pattern**: Agent starts with zero context and wastes time exploring.

### 2. Model: The reasoning engine

- Claude Opus for complex reasoning
- Claude Sonnet for balanced capability
- Claude Haiku for fast, simple tasks

**High leverage**: Match model capability to task complexity.

**Anti-pattern**: Using Opus for simple tasks (slow, expensive) or Haiku for complex reasoning (fails).

### 3. Prompt: Your instructions to the agent

- System prompts define behavior
- User prompts define tasks
- Agentic prompts contain tool sequences

**High leverage**: Clear, specific prompts with examples.

**Anti-pattern**: Vague prompts that require iteration.

### 4. Tools: Capabilities for action

- Read/Write/Edit for file operations
- Bash for command execution
- MCP servers for external integrations

**High leverage**: Right tools available for the task.

**Anti-pattern**: Agent lacks tools needed to complete work.

---

## Through-Agent Leverage Points (5-12)

### 5. Standard Out: Clear logging throughout applications

**Why it matters**: Without stdout, agent cannot see errors or understand state. This is often the missing link when agents fail.

**High leverage pattern**:

```python
try:
    result = process(data)
    print(f"SUCCESS: Processed {len(result)} items")
    return result
except Exception as e:
    print(f"ERROR: {str(e)}")
    raise
```yaml

**Anti-pattern**: Silent functions that return without logging. Agent has no visibility into what happened.

### 6. Types

**Information Dense Keywords (IDKs)**

Types trace the flow of information through your codebase. They represent concrete pieces of data.

**High leverage pattern**:

- `DatabaseSchemaResponse` - tells a story
- `FileUploadRequest` - searchable, meaningful
- `UserAuthToken` - clear purpose

**Anti-pattern**: Generic names like `DataRequest`, `QueryResponse` - agent gets lost searching.

### 7. Documentation

**Agent-specific context**

Two types:

- **Internal**: Docs in your codebase (README, CLAUDE.md, comments)
- **External**: References to libraries, APIs, frameworks

**High leverage**: Documentation written for agents, not just humans.

**Anti-pattern**: No docs, or docs that assume context the agent doesn't have.

### 8. Tests

**Validation and self-correction**

**This is the highest leverage point!**

If agent runs tests, it can:

- Self-validate its changes
- Fix issues without human intervention
- Achieve one-shot success

**High leverage pattern**: Tests that run quickly and provide clear pass/fail feedback.

**Anti-pattern**: No tests, or tests that are slow/flaky.

### 9. Architecture

**Consistent, navigable codebase structure**

Guidelines for agent-friendly architecture:

- Clear entry points (`server.py`, `main.ts`)
- Client/server separation (cuts search space in half)
- File size < 1000 lines (token efficiency)
- Mirror test structure with source
- Verbose, information-dense naming
- Single responsibility per file
- Consistent patterns throughout

**Anti-pattern**: Inconsistent structure, huge files, unclear organization.

### 10. Plans

**Meta-work communication**

Plans are prompts. They're how you communicate massive amounts of work to agents.

**High leverage**: Detailed plans with clear steps and success criteria.

**Anti-pattern**: No plan, or plans that assume agent understands implicit context.

### 11. Templates

**Reusable prompts**

Slash commands solve the "three times = automate" problem.

**High leverage**: Templates for common workflows that encode your expertise.

**Anti-pattern**: Retyping the same instructions repeatedly.

### 12. ADWs (AI Developer Workflows)

**Prompts + code + triggers running autonomously**

The pinnacle of agentic coding: workflows that run without you.

**High leverage**: Automated workflows triggered by events (commits, PRs, schedules).

**Anti-pattern**: Manual invocation for every task.

---

## Quick Reference Table

| # | Leverage Point | Category | Direction | Key Question |
| --- | ---------------- | ---------- | ----------- | -------------- |
| 1 | Context | In-Agent | More is better | What does agent see? |
| 2 | Model | In-Agent | Match to task | Right capability? |
| 3 | Prompt | In-Agent | Clarity | Clear instructions? |
| 4 | Tools | In-Agent | Availability | Can agent act? |
| 5 | Standard Out | Through-Agent | Visibility | Can agent see errors? |
| 6 | Types | Through-Agent | Searchability | Can agent trace data? |
| 7 | Documentation | Through-Agent | Agent-focused | Can agent understand? |
| 8 | Tests | Through-Agent | Self-correction | Can agent validate? |
| 9 | Architecture | Through-Agent | Navigability | Can agent find things? |
| 10 | Plans | Through-Agent | Communication | Does agent know the work? |
| 11 | Templates | Through-Agent | Reusability | Is work automated? |
| 12 | ADWs | Through-Agent | Autonomy | Does it run without you? |

---

## Priority Order for Improvement

When improving agentic coding capability, address in this order:

1. **Tests** (highest leverage - enables self-correction)
2. **Standard Out** (visibility - agent can see errors)
3. **Architecture** (navigability - efficient context usage)
4. **Types** (searchability - trace data flow)
5. **Documentation** (understanding - agent-friendly context)
6. **Templates** (reusability - automate repeated work)
7. **Plans** (communication - complex task breakdown)
8. **ADWs** (autonomy - fully automated workflows)

---

## Related

- @tac-philosophy.md - Core TAC philosophy
- @core-four-framework.md - The Core Four in detail
- @agentic-kpis.md - How to measure improvement
- @agent-perspective-checklist.md - Checklist before tasks

---

**Source:** Lesson 002 - 12 Leverage Points of Agentic Coding
**Last Updated:** 2025-12-04
