# Lesson NNN: [Title] - Implementation Plan

**Created:** YYYY-MM-DD
**Status:** Draft | In Progress | Complete
**Companion Repo:** `D:\repos\gh\disler\{repo-name}`

---

## Lesson Summary

- **Core Tactic**: [One-sentence description of the main teaching]
- **Key Frameworks**: [List any frameworks introduced: PITER, R&D, etc.]

---

## Source Materials Reviewed

- [ ] `lessons/lesson-NNN-*/lesson.md`
- [ ] `lessons/lesson-NNN-*/captions.txt` (transcript - authoritative)
- [ ] `lessons/lesson-NNN-*/links.md`
- [ ] `lessons/lesson-NNN-*/repos.md`
- [ ] `lessons/lesson-NNN-*/images/`
- [ ] `analysis/lesson-NNN-analysis.md`
- [ ] `analysis/CONSOLIDATION.md` (relevant sections)
- [ ] `analysis/DOCUMENTATION_AUDIT.md` (relevant sections)
- [ ] Companion repo explored

---

## Components to Implement

### Skills

| Name | Purpose | allowed-tools | Priority |
| ------ | --------- | --------------- | ---------- |
| `skill-name` | What it does | Read, Grep, Glob | P1/P2/P3 |

### Agents

| Name | Purpose | tools | model | Priority |
| ------ | --------- | ------- | ------- | ---------- |
| `agent-name` | What it does | [Read, Write, Bash] | sonnet | P1/P2/P3 |

### Commands

| Name | Purpose | Arguments | Priority |
| ------ | --------- | ----------- | ---------- |
| `/command-name` | What it does | `$ARGUMENTS` or `$1 $2` | P1/P2/P3 |

### Memory Files

| Name | Purpose | Load Condition | Priority |
| ------ | --------- | ---------------- | ---------- |
| `file-name.md` | What it provides | When user asks about X | P1/P2/P3 |

### Other Components

| Type | Name | Purpose | Priority |
| ------ | ------ | --------- | ---------- |
| Hook | `hook-name` | When to trigger | P1/P2/P3 |
| Output Style | `style-name` | How to format output | P1/P2/P3 |
| MCP Config | `config-name` | What service to connect | P1/P2/P3 |

---

## Implementation Order

1. [First component - usually foundational skill]
2. [Component that depends on #1]
3. [etc.]

---

## Memory File Content Specifications

For each memory file, document:

### 1. [memory-file-name.md]

**Purpose**: [What this memory file provides to the agent]

**Content Outline**:

- [Key concept 1]
- [Key concept 2]
- [Framework or pattern to encode]
- [Reference material or examples]

*Repeat for each memory file in the lesson.*

---

## SDK-Only Components (Lessons 11-12 Only)

> **Note**: Skip this section for lessons 1-10. Only relevant when components require agent spawning or orchestration patterns.

If any proposed components require spawning other agents (orchestrators, fleet managers, multi-agent coordination):

| Component | Why SDK-Only | Implementation Path |
| ----------- | -------------- | --------------------- |
| [component-name] | [Reason: needs to spawn agents, manage lifecycle, etc.] | Claude Agent SDK + [approach] |

**Guidance**: These components cannot be Claude Code subagents. Document as:

1. Reference implementations (point to companion repo)
2. Guidance skills (help users build SDK solutions)
3. Memory files (encode patterns for reference)

---

## Documentation Validation (MANDATORY)

### docs-management Skill Invocations

Before finalizing this plan, the following docs-management queries MUST be executed:

#### Skills Validation
- [ ] Invoked: `find_docs.py search skill frontmatter allowed-tools`
- Result: [Document findings - e.g., "Confirmed allowed-tools must be comma-separated string"]

#### Agents Validation
- [ ] Invoked: `find_docs.py search subagent tools model frontmatter`
- Result: [Document findings - e.g., "Confirmed tools can be array or comma-separated, model is optional"]

#### Commands Validation
- [ ] Invoked: `find_docs.py search slash command frontmatter description`
- Result: [Document findings - e.g., "Confirmed description and argument-hint are valid frontmatter fields"]

#### Hooks Validation (if applicable)
- [ ] Invoked: `find_docs.py search hook events PreToolUse matcher`
- Result: [Document findings]

### Official Documentation References

| Component | Official Doc Source | Key Requirement Verified |
| ----------- | --------------------- | -------------------------- |
| Skills | code.claude.com/docs/en/skills | allowed-tools is comma-separated |
| Agents | code.claude.com/docs/en/sub-agents | tools field, model selection |
| Commands | code.claude.com/docs/en/slash-commands | frontmatter fields |

---

## Validation Criteria

- [ ] All components pass docs-management validation (see section above)
- [ ] TypeScript SDK patterns used (not Python)
- [ ] No duplicate functionality with existing plugins
- [ ] Naming conventions followed (noun-phrase skills, verb-phrase commands, kebab-case)
- [ ] Skill `allowed-tools` is comma-separated (not array)
- [ ] Agent `tools` is array or comma-separated
- [ ] Agent `model` is opus/sonnet/haiku/inherit (use opus for planning/orchestration)
- [ ] Model IDs are Dec 2025 versions

---

## Python-to-TypeScript Transformations Required

| Python Pattern (from repo) | TypeScript Equivalent |
| ---------------------------- | ---------------------- |
| `@tool` decorator | `tool()` with Zod schemas |
| `ClaudeSDKClient` | `query()` async generator |
| `snake_case` options | `camelCase` options |

---

## Key Patterns from Companion Repo

### CLAUDE.md Patterns

[Document any memory file patterns found]

### ADW/Workflow Patterns

[Document any Agent-Driven Workflow patterns]

### Hooks/Configs

[Document any hook implementations or configurations]

### Prompt Templates

[Document any slash commands or system prompts]

---

## Dependencies

### Builds On

- [Previous lessons this depends on]

### Required By

- [Future lessons that need this]

---

## Notes

[Any special considerations, blockers, decisions, or open questions]

---

## Completion Checklist

- [ ] All source materials reviewed
- [ ] Companion repo explored
- [ ] docs-management skill invoked for validation
- [ ] All components listed with priorities
- [ ] Implementation order defined
- [ ] Python-to-TypeScript transformations documented
- [ ] Plan reviewed and approved

---

**Plan Status**: Draft | In Progress | Ready for Implementation | Complete
