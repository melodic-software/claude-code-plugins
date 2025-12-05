# Lesson 002: 12 Leverage Points - Implementation Plan

**Created:** 2025-12-04
**Status:** Complete
**Companion Repo:** `D:\repos\gh\disler\tac-2`

---

## Lesson Summary

- **Core Tactic**: **Adopt Your Agent's Perspective** - Your agent is brilliant but blind. With every new session, it starts as a blank instance. Give it the context, model, prompt, and tools (Core Four) plus 8 external leverage points to maximize autonomous success.
- **Key Frameworks**:
  - The 12 Leverage Points (4 In-Agent + 8 Through-Agent)
  - Agentic Coding KPIs (Size, Attempts, Streak, Presence)
  - Phase 2 SDLC (Plan -> Code -> Test -> Review -> Document)

---

## Source Materials Reviewed

- [x] `lessons/lesson-002-12-leverage-points-of-agentic-coding/lesson.md`
- [x] `lessons/lesson-002-12-leverage-points-of-agentic-coding/captions.txt` (transcript - authoritative)
- [x] `lessons/lesson-002-12-leverage-points-of-agentic-coding/links.md`
- [x] `lessons/lesson-002-12-leverage-points-of-agentic-coding/repos.md`
- [x] `lessons/lesson-002-12-leverage-points-of-agentic-coding/images/`
- [x] `analysis/lesson-002-analysis.md`
- [x] `analysis/CONSOLIDATION.md` (relevant sections)
- [x] `analysis/DOCUMENTATION_AUDIT.md` (relevant sections)
- [x] Companion repo explored (tac-2)

---

## Components to Implement

### Skills

| Name | Purpose | allowed-tools | Priority |
| ------ | --------- | --------------- | ---------- |
| `leverage-point-audit` | Audit codebase for 12 leverage point coverage, identify gaps, provide prioritized recommendations | Read, Grep, Glob | P1 |
| `standard-out-setup` | Guide adding console output/logging to make errors visible to agents | Read, Edit, Grep | P2 |

### Agents

| Name | Purpose | tools | model | Priority |
| ------ | --------- | ------- | ------- | ---------- |
| *None* | Lesson 2 teaches concepts, not specialized agent workflows | N/A | N/A | N/A |

**Rationale**: No specific agents for Lesson 002. The lesson introduces the 12 leverage points framework but doesn't define specialized agent workflows. Agents appear in later lessons.

### Commands

| Name | Purpose | Arguments | Priority |
| ------ | --------- | ----------- | ---------- |
| `/prime` | Prime agent with codebase context (git ls-files, README, summarize) | None | P1 |
| `/tools` | List available Claude Code tools with parameters | None | P2 |

### Memory Files

| Name | Purpose | Load Condition | Priority |
| ------ | --------- | ---------------- | ---------- |
| `12-leverage-points.md` | Complete reference of all 12 leverage points with examples | When improving agentic coding or auditing codebase | P1 |
| `agentic-kpis.md` | KPI definitions: Size, Attempts, Streak, Presence | When measuring agentic success | P1 |
| `agent-perspective-checklist.md` | Checklist to adopt agent's perspective before tasks | Before starting agentic work | P2 |

### Other Components

| Type | Name | Purpose | Priority |
| ------ | ------ | --------- | ---------- |
| *None* | N/A | No hooks, output styles, or MCP configs for this lesson | N/A |

---

## Implementation Order

1. `12-leverage-points.md` - Core framework reference (foundational)
2. `agentic-kpis.md` - Measurement framework
3. `agent-perspective-checklist.md` - Practical checklist
4. `leverage-point-audit` skill - Apply the framework
5. `/prime` command - Core utility command
6. `/tools` command - Tool awareness command
7. `standard-out-setup` skill - Specific leverage point implementation

---

## Memory File Content Specifications

### 1. 12-leverage-points.md

**Purpose**: Complete reference of the 12 leverage points framework.

**Content Outline**:

- Introduction: Why leverage points matter
- Two categories: In-Agent (Core Four) vs Through-Agent (8 external)
- In-Agent leverage points:
  1. Context - What can your agent see?
  2. Model - The reasoning engine
  3. Prompt - Your instructions to the agent
  4. Tools - Capabilities for action
- Through-Agent leverage points:
  5. Standard Out - Logging for agent visibility
  6. Types - Information Dense Keywords (IDKs)
  7. Documentation - Agent-specific context
  8. Tests - Validation and self-correction (highest leverage!)
  9. Architecture - Consistent, navigable codebase structure
  10. Plans - Meta-work communication
  11. Templates - Reusable prompts (slash commands)
  12. ADWs - AI Developer Workflows (prompts + code + triggers)
- Common anti-patterns
- Quick reference table

### 2. agentic-kpis.md

**Purpose**: Define and explain the four KPIs for measuring agentic coding success.

**Content Outline**:

- Why KPIs matter for agentic coding
- The four KPIs:
  - **Size** (UP): Increase size of work handed to agents (5 min -> 30 min -> 3 hours)
  - **Attempts** (DOWN): One-shot success, target = 1
  - **Streak** (UP): Consecutive one-shot wins
  - **Presence** (DOWN): Minimize human intervention, target = 0
- How to measure each KPI
- What to do when metrics slip
- Example scenarios

### 3. agent-perspective-checklist.md

**Purpose**: Practical checklist to adopt before starting agentic work.

**Content Outline**:

- Pre-task questions from the agent's perspective
- Context checklist: Does agent have what it needs?
- Visibility checklist: Can agent see errors?
- Validation checklist: Can agent self-correct?
- Architecture checklist: Can agent navigate efficiently?
- Quick reference card

---

## Skill Content Specifications

### 1. leverage-point-audit skill

**Purpose**: Audit a codebase for 12 leverage point coverage.

**Workflow**:

1. Scan for CLAUDE.md files (Context)
2. Check for stdout/logging patterns (Standard Out)
3. Check for type definitions (Types/IDKs)
4. Check for documentation files (Documentation)
5. Check for test files (Tests)
6. Analyze architecture patterns (Architecture)
7. Check for slash commands/templates (Templates)
8. Generate prioritized recommendations

**allowed-tools**: Read, Grep, Glob

### 2. standard-out-setup skill

**Purpose**: Guide adding console output to make errors visible to agents.

**Workflow**:

1. Identify API endpoints or main functions
2. Check for existing logging
3. Recommend stdout patterns for success/error visibility
4. Show before/after examples

**allowed-tools**: Read, Edit, Grep

---

## Command Content Specifications

### 1. /prime command

**Purpose**: Prime agent with codebase understanding.

**Pattern** (from tac-2):

```markdown
Execute to understand codebase structure:
1. Run: git ls-files
2. Read: README.md
3. Summarize your understanding of the codebase
```markdown

### 2. /tools command

**Purpose**: List available Claude Code tools.

**Pattern** (from tac-2):

```markdown
List all available tools with their parameters and capabilities.
Display as TypeScript function signatures.
```yaml

---

## Python-to-TypeScript Transformations Required

| Python Pattern (from repo) | TypeScript Equivalent |
| ---------------------------- | ---------------------- |
| Pydantic models (`BaseModel`) | TypeScript interfaces + Zod schemas |
| `@app.post("/api/...")` | Express/Fastify routes |
| `subprocess.run(["claude", "-p", ...])` | `$\`claude -p ${...}\`` (Bun shell) |

**Note**: tac-2 is a full-stack app (FastAPI + TypeScript client). Components extracted for the plugin are framework-agnostic patterns.

---

## Key Patterns from Companion Repo (tac-2)

### Permission Configuration

```json
{
  "permissions": {
    "allow": ["Read", "Write", "Edit", "Bash(uv run:*)", "Bash(git checkout:*)", ...],
    "deny": ["Bash(git push --force:*)", ...]
  }
}
```markdown

### /prime Command Pattern

```markdown
Execute to understand codebase structure then summarize:
1. Run: git ls-files
2. Read: README.md
3. Summarize understanding of codebase
```markdown

### Standard Out Pattern (Critical)

```python
# BAD - Agent can't see what happened
def upload_data(file):
    return convert_csv(file)  # Silent!

# GOOD - Agent can see success AND errors
def upload_data(file):
    try:
        result = convert_csv(file)
        print(f"SUCCESS: Converted {len(result)} rows")
        return result
    except Exception as e:
        print(f"ERROR: {str(e)}")
        raise
```yaml

---

## Dependencies

### Builds On

- Lesson 001: Core Four framework, Stop Coding tactic

### Required By

- Lesson 003: Plans as leverage point (meta-prompts)
- Lesson 004: ADWs expanded (AFK agents)
- Lesson 005: Tests as highest leverage (dedicated testing)
- Lesson 006: Agent specialization (one purpose)
- Lesson 007: Zero presence target (ZTE)

---

## Validation Criteria

- [x] All components pass docs-management validation
- [x] TypeScript SDK patterns used where applicable
- [x] No duplicate functionality with existing plugins
- [x] Naming conventions followed (noun-phrase skills, verb-phrase commands, kebab-case)
- [x] Skill `allowed-tools` is comma-separated (not array)
- [ ] Memory files tested for proper loading
- [ ] Skills tested for activation

---

## Notes

1. **Lesson 2 is conceptual but actionable** - Unlike Lesson 1 (pure philosophy), Lesson 2 introduces the 12 leverage points framework with concrete patterns that can be encoded.

2. **Skills focus on auditing and setup** - The `leverage-point-audit` skill applies the framework; `standard-out-setup` addresses the most critical leverage point.

3. **Commands from tac-2** - The `/prime` and `/tools` commands are directly from the companion repo and represent essential utilities.

4. **Memory files are reference material** - These encode the frameworks for quick reference during agentic work.

5. **No agents yet** - Agent patterns emerge in Lesson 4+. This lesson teaches concepts.

---

## Completion Checklist

- [x] All source materials reviewed
- [x] Companion repo explored
- [x] docs-management skill invoked for validation
- [x] All components listed with priorities
- [x] Implementation order defined
- [x] Python-to-TypeScript transformations documented
- [x] Plan reviewed and approved

---

**Plan Status**: Ready for Implementation
