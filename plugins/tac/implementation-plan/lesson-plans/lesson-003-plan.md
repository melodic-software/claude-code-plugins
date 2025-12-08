# Lesson 003: Success is Planned - Implementation Plan

**Created:** 2025-12-04
**Status:** Ready for Implementation
**Companion Repo:** `D:\repos\gh\disler\tac-3`

---

## Lesson Summary

- **Core Tactic**: Template Your Engineering - encode problem-solving patterns into reusable meta-prompts and plans
- **Key Frameworks**: Prompt Hierarchy (High-Level -> Meta-Prompt -> Plan -> HOP), Fresh Agent Instances, 80-20 of Agentic Coding

---

## Source Materials Reviewed

- [x] `lessons/lesson-003-success-is-planned/lesson.md`
- [x] `lessons/lesson-003-success-is-planned/captions.txt` (transcript - 46:32 of content)
- [x] `lessons/lesson-003-success-is-planned/links.md`
- [x] `lessons/lesson-003-success-is-planned/repos.md`
- [x] `analysis/lesson-003-analysis.md`
- [x] `analysis/CONSOLIDATION.md` (relevant sections)
- [x] `analysis/DOCUMENTATION_AUDIT.md` (relevant sections)
- [x] Companion repo explored (tac-3)

---

## Components to Implement

### Skills

| Name | Purpose | allowed-tools | Priority |
| ------ | --------- | --------------- | ---------- |
| `template-engineering` | Guide creation of meta-prompt templates with proper anatomy | Read, Grep, Glob | P1 |
| `plan-generation` | Assist in generating plans from templates using reasoning mode | Read, Grep, Glob | P1 |

### Agents

| Name | Purpose | tools | model | Priority |
| ------ | --------- | ------- | ------- | ---------- |
| `plan-generator` | Generate plans from templates using extended thinking | [Read, Write, Glob, Grep] | sonnet | P2 |
| `plan-implementer` | Execute generated plans with validation | [Read, Write, Edit, Bash] | sonnet | P2 |

### Commands

| Name | Purpose | Arguments | Priority |
| ------ | --------- | ----------- | ---------- |
| `/chore` | Generate chore plan from meta-prompt template | `$ARGUMENTS` - chore description | P1 |
| `/bug` | Generate bug fix plan from meta-prompt template | `$ARGUMENTS` - bug description | P1 |
| `/feature` | Generate feature plan from meta-prompt template | `$ARGUMENTS` - feature description | P1 |
| `/implement` | Execute a generated plan (HOP pattern) | `$ARGUMENTS` - path to plan file | P1 |

**Note:** `/prime` already exists from Lesson 002 - no need to recreate.

### Memory Files

| Name | Purpose | Load Condition | Priority |
| ------ | --------- | ---------------- | ---------- |
| `template-engineering.md` | Template anatomy and meta-prompt design patterns | When creating templates | P1 |
| `meta-prompt-patterns.md` | Meta-prompt and Higher-Order Prompt patterns | When building prompt hierarchies | P1 |
| `plan-format-guide.md` | Standard plan format sections for chores, bugs, features | When generating/reviewing plans | P1 |
| `fresh-agent-rationale.md` | Why and when to use fresh agent instances | When deciding agent lifecycle | P2 |

### Other Components

None for this lesson.

---

## Implementation Order

1. **Memory Files First** (foundation for skills and commands)
   - `template-engineering.md` - core concepts
   - `meta-prompt-patterns.md` - prompt hierarchy
   - `plan-format-guide.md` - plan structures
   - `fresh-agent-rationale.md` - agent lifecycle

2. **Skills Second** (guidance for template creation)
   - `template-engineering` skill
   - `plan-generation` skill

3. **Commands Third** (the meta-prompts themselves)
   - `/chore` command
   - `/bug` command
   - `/feature` command
   - `/implement` command (HOP)

4. **Agents Last** (optional - can delegate to skills)
   - `plan-generator` agent
   - `plan-implementer` agent

---

## Memory File Content Specifications

### 1. template-engineering.md

**Purpose**: Core reference for creating meta-prompt templates

**Content Outline**:

- What is a meta-prompt (prompt that builds a prompt)
- Template anatomy:
  - Purpose section (clear description at top)
  - Instructions section (detailed guidance)
  - Relevant Files section (file paths to focus on)
  - Plan Format section (markdown template with placeholders)
  - Parameter section (`$ARGUMENTS` for user input)
- Design principles:
  - Solve problem classes, not individual problems
  - Encode team best practices
  - Include validation commands
- Examples from tac-3 (chore, bug, feature templates)
- Anti-patterns to avoid

### 2. meta-prompt-patterns.md

**Purpose**: Prompt hierarchy and composition patterns

**Content Outline**:

- The Prompt Hierarchy:
  - Level 1: High-Level Prompt (simple description)
  - Level 2: Meta-Prompt (prompt that builds prompt)
  - Level 3: Plan (generated detailed specification)
  - Level 4: Higher-Order Prompt (HOP - prompt accepting prompt as input)
- Composition patterns:
  - Simple meta-prompt (one input, one output)
  - Composable commands (e.g., `/install` calling `/prime`)
  - HOPs for plan execution (`/implement`)
- "Think hard" activation for reasoning model
- Flow: high-level -> template -> plan -> implement

### 3. plan-format-guide.md

**Purpose**: Standard plan structures for different work types

**Content Outline**:

- Chore Plan Format:

  ```markdown
  # Chore: <name>
  ## Chore Description
  ## Relevant Files
  ## Step by Step Tasks
  ## Validation Commands
  ## Notes
  ```

- Bug Plan Format:

  ```markdown
  # Bug: <name>
  ## Bug Description
  ## Problem Statement
  ## Solution Statement
  ## Steps to Reproduce
  ## Root Cause Analysis
  ## Relevant Files
  ## Step by Step Tasks
  ## Validation Commands
  ## Notes
  ```

- Feature Plan Format:

  ```markdown
  # Feature: <name>
  ## Feature Description
  ## User Story
  ## Problem Statement
  ## Solution Statement
  ## Relevant Files
  ## Implementation Plan (Foundation, Core, Integration)
  ## Step by Step Tasks
  ## Testing Strategy (Unit, Integration, Edge Cases)
  ## Acceptance Criteria
  ## Validation Commands
  ## Notes
  ```

- Why each section matters
- Output location: `specs/*.md`

### 4. fresh-agent-rationale.md

**Purpose**: Why and when to use fresh agent instances

**Content Outline**:

- Three critical reasons:
  1. **Free Context**: Focus every available token on the task
  2. **Force Isolation**: Make templates reusable with zero dependencies
  3. **Prepare for Off-Device**: Enable true AFK agentic coding
- When to use fresh instances:
  - Each phase of SDLC (Plan -> Code -> Test -> Review -> Document)
  - After completing a distinct work unit
  - When context window is depleted
- Anti-pattern: Stretching one agent across entire SDLC
- Connection to PITER framework (Lesson 4)

---

## Validation Criteria

- [x] All components pass docs-management validation (confirmed in Phase 3)
- [x] No duplicate functionality with existing plugins
- [x] Naming conventions followed (noun-phrase skills, verb-phrase commands, kebab-case)
- [x] Skill `allowed-tools` is comma-separated (not array)
- [x] Agent `tools` is array
- [ ] Model IDs are Dec 2025 versions (use in agent frontmatter)

---

## Python-to-TypeScript Transformations Required

No SDK code in this lesson - primarily slash commands and memory files.

| Python Pattern (from repo) | TypeScript Equivalent |
| ---------------------------- | ---------------------- |
| N/A - this lesson uses CLI commands | N/A |

---

## Key Patterns from Companion Repo

### CLAUDE.md Patterns

No CLAUDE.md in tac-3 - context comes from templates themselves.

### Prompt Templates (Slash Commands)

From `.claude/commands/` in tac-3:

1. **chore.md** - Chore meta-prompt template
2. **bug.md** - Bug meta-prompt template
3. **feature.md** - Feature meta-prompt template
4. **implement.md** - Higher-Order Prompt for plan execution
5. **prime.md** - Context priming (already implemented in Lesson 002)
6. **install.md** - Composable command pattern

### Plan Output Pattern

Plans are written to `specs/*.md` with validation commands section.

### Permission Configuration

```json
{
  "permissions": {
    "allow": ["Bash(mkdir:*)", "Bash(uv:*)", "Write", "Bash(chmod:*)"],
    "deny": ["Bash(git push --force:*)", "Bash(rm -rf:*)"]
  }
}
```yaml

---

## Dependencies

### Builds On

- **Lesson 001**: Stop coding - now use templates to automate planning too
- **Lesson 002**: 12 leverage points - templates are leverage point #11

### Required By

- **Lesson 004**: Off-device agentic coding with PITER framework
- **Lesson 005**: Validation commands create closed loops
- **Lesson 007**: Fresh agent instances -> ZTE (Zero Touch Engineering)

---

## Notes

1. **`/prime` already exists** - Created in Lesson 002, no need to duplicate
2. **Agents are optional** - The commands can work standalone without dedicated agents
3. **Specs directory pattern** - Consider documenting that plans go to `specs/*.md` but this is project-specific
4. **"Think hard" pattern** - Include in command instructions to activate reasoning model
5. **Composable commands** - The `/install` pattern (calling `/prime` internally) is advanced - document in memory file but not implement as separate command

---

## Completion Checklist

- [x] All source materials reviewed
- [x] Companion repo explored
- [x] docs-management skill invoked for validation
- [x] All components listed with priorities
- [x] Implementation order defined
- [x] Memory file content specified
- [ ] Implementation completed
- [ ] MASTER-TRACKER updated

---

**Plan Status**: Ready for Implementation
