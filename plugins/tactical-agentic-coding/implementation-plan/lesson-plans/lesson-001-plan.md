# Lesson 001: Hello Agentic Coding - Implementation Plan

**Created:** 2025-12-04
**Status:** Complete
**Companion Repo:** `D:\repos\gh\disler\tac-1`

---

## Lesson Summary

- **Core Tactic**: **Stop Coding** - Your hands and mind are no longer the best tools for writing code. Language models wrapped in agent architecture are superior coders. Use the best tool for the job.
- **Key Frameworks**:
  - The Core Four (Context, Model, Prompt, Tools)
  - Phase 1 (AI Coding) vs Phase 2 (Agentic Coding)
  - Commander of Compute mindset

---

## Source Materials Reviewed

- [x] `lessons/lesson-001-hello-agentic-coding/lesson.md`
- [x] `lessons/lesson-001-hello-agentic-coding/captions.txt` (transcript - authoritative)
- [x] `lessons/lesson-001-hello-agentic-coding/links.md`
- [x] `lessons/lesson-001-hello-agentic-coding/repos.md`
- [x] `lessons/lesson-001-hello-agentic-coding/images/`
- [x] `analysis/lesson-001-analysis.md`
- [x] `analysis/CONSOLIDATION.md` (relevant sections)
- [x] `analysis/DOCUMENTATION_AUDIT.md` (relevant sections)
- [x] Companion repo explored (tac-1)

---

## Components to Implement

### Skills

| Name | Purpose | allowed-tools | Priority |
| ------ | --------- | --------------- | ---------- |
| *None* | Lesson 1 is foundational philosophy, no specific workflow | N/A | N/A |

**Rationale**: Lesson 1 establishes mindset rather than actionable workflows. Skills are better suited for lessons 3+ where specific techniques are introduced.

### Agents

| Name | Purpose | tools | model | Priority |
| ------ | --------- | ------- | ------- | ---------- |
| *None* | Foundational philosophy lesson | N/A | N/A | N/A |

**Rationale**: No specific agent patterns in this lesson. Agents come in later lessons (4+).

### Commands

| Name | Purpose | Arguments | Priority |
| ------ | --------- | ----------- | ---------- |
| *None* | No specific command pattern | N/A | N/A |

**Rationale**: Commands require actionable workflows. Lesson 1 is conceptual.

### Memory Files

| Name | Purpose | Load Condition | Priority |
| ------ | --------- | ---------------- | ---------- |
| `tac-philosophy.md` | Core TAC philosophy: stop coding, build systems that build systems, commander of compute | Always - foundational mindset | P1 |
| `core-four-framework.md` | The Core Four (Context, Model, Prompt, Tools) framework definition | When discussing agentic fundamentals | P1 |
| `programmable-claude-patterns.md` | Patterns for running Claude Code from shell/Python/TypeScript | When building automation scripts | P2 |

### Other Components

| Type | Name | Purpose | Priority |
| ------ | ------ | --------- | ---------- |
| *None* | N/A | No hooks, output styles, or MCP configs for foundational lesson | N/A |

---

## Implementation Order

1. `tac-philosophy.md` - Core mindset (foundational)
2. `core-four-framework.md` - Core Four framework (foundational)
3. `programmable-claude-patterns.md` - Automation patterns (builds on foundation)

---

## Validation Criteria

- [x] All components pass docs-management validation (memory files only need valid markdown)
- [x] TypeScript SDK patterns used where applicable (N/A for memory files)
- [x] No duplicate functionality with existing plugins
- [x] Naming conventions followed (kebab-case file names)
- [ ] Memory files tested for proper loading and import

---

## Python-to-TypeScript Transformations Required

| Python Pattern (from repo) | TypeScript Equivalent |
| ---------------------------- | ---------------------- |
| `subprocess.run(["claude", "-p", prompt])` | `$\`claude -p ${prompt}\`` (Bun shell) |
| `with open("file.md") as f:` | `readFileSync("file.md", "utf-8")` |

**Note**: These are documented in `programmable-claude-patterns.md` for reference.

---

## Key Patterns from Companion Repo (tac-1)

### CLAUDE.md Patterns

- **None in tac-1** - Intentionally minimal for foundational lesson. Focus on core concepts.

### Permission Configuration

```json
{
  "permissions": {
    "allow": [
      "Read", "Write", "Edit",
      "Bash(uv run:*)",
      "Bash(git checkout:*)", "Bash(git branch:*)",
      "Bash(git add:*)", "Bash(git commit:*)",
      "WebSearch"
    ]
  }
}
```markdown

### Prompt Language Syntax

- `RUN:` - Command execution blocks
- `CREATE:` - File creation blocks
- `REPORT:` - Output expectation blocks

### Contrast Pattern (AI vs Agentic)

**AI Coding (Phase 1)**:

```markdown
CREATE main_aic.py:
    print goodbye ai coding
```markdown

**Agentic Coding (Phase 2)**:

```markdown
RUN:
    checkout a new/existing "demo-agentic-coding" git branch
CREATE main_tac.py:
    print "hello agentic coding"
RUN:
    uv run main_tac.py
    git add . && git commit -m "Demo"
```yaml

---

## Dependencies

### Builds On

- None (first lesson)

### Required By

- Lesson 002: 12 Leverage Points (where to apply Core Four)
- Lesson 003: Success is Planned (how to structure agent work)
- Lesson 004: AFK Agents (closed loop structures)
- All subsequent lessons build on this foundation

---

## Memory File Content Specifications

### 1. tac-philosophy.md

**Purpose**: Core TAC philosophy loaded always as foundational mindset guidance.

**Content Outline**:

- Mission: Become the engineer they can't replace
- Tactic #1: Stop Coding
- Phase 1 vs Phase 2 distinction
- Commander of Compute mindset
- Building systems that build systems
- Engineering was never about writing code

### 2. core-four-framework.md

**Purpose**: Define the Core Four framework for agentic coding.

**Content Outline**:

- The Big Three (AI Coding): Context, Model, Prompt
- The Core Four (Agentic Coding): Context, Model, Prompt, **Tools**
- How tools enable long-running workflows
- Examples of each element

### 3. programmable-claude-patterns.md

**Purpose**: Patterns for invoking Claude Code programmatically.

**Content Outline**:

- Shell execution: `claude -p "$PROMPT"`
- Python execution: `subprocess.run(["claude", "-p", prompt])`
- TypeScript execution: `$\`claude -p ${prompt}\``
- Permission configuration patterns
- When to use programmatic invocation

---

## Notes

1. **Lesson 1 is deliberately minimal** - It establishes mindset, not techniques. The analysis correctly identifies that skills/agents/commands should wait for later lessons with actionable workflows.

2. **Memory files are the primary output** - This lesson's value is encoded in foundational memory files that inform all subsequent work.

3. **No TypeScript SDK usage** - This lesson predates SDK patterns. SDK comes in Lesson 11.

4. **Programmable patterns are reference material** - Not meant to be executed by the plugin, but documented for users who want to build automation.

---

## Completion Checklist

- [x] All source materials reviewed
- [x] Companion repo explored
- [x] docs-management skill invoked for validation (memory files are standard markdown)
- [x] All components listed with priorities
- [x] Implementation order defined
- [x] Python-to-TypeScript transformations documented
- [x] Plan reviewed and approved

---

**Plan Status**: Ready for Implementation
