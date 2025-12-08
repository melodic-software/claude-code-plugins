# Tactical Agentic Coding - Lesson Analysis SOP

This document defines the standard operating procedure for analyzing each TAC lesson and extracting Claude Code plugin components (skills, subagents, commands, memory files).

## Overview

Each lesson in the TAC course teaches specific agentic coding principles. Our goal is to:

1. **Understand** the lesson content deeply (video captions, written lesson, images)
2. **Analyze** the companion repository for implementation patterns
3. **Extract** actionable Claude Code components that embody the lesson's teachings
4. **Validate** against official Claude Code documentation
5. **Build** properly structured plugin components

## Pre-Analysis Setup

### Required Context

Before analyzing any lesson, ensure access to:

- Lesson files in `plugins/tac/lessons/lesson-NNN-*/`
- Companion repository in `D:/repos/gh/disler/{repo-name}`
- Official Claude Code documentation via `docs-management` skill

### Lesson File Structure

Each lesson folder contains:

| File | Purpose |
| ---- | ------- |
| `lesson.md` | Written summary with key concepts, tactics, frameworks |
| `captions.txt` | Full video transcript - primary source of detailed content |
| `video.md` | Video metadata (title, duration, URL) |
| `links.md` | External resources and key concept tables |
| `repos.md` | Companion repository information |
| `images/*.jpg` | Visual aids (tactic cards, diagrams) |

## Analysis Workflow

### Phase 1: Content Ingestion

#### Step 1.1: Read Lesson Files

Read all lesson files in order:

1. `video.md` - Get context (title, duration, what to expect)
2. `lesson.md` - Read structured summary first
3. `links.md` - Review key concept tables and frameworks
4. `captions.txt` - Deep dive into full transcript
5. `images/` - View any visual aids

#### Step 1.2: Explore Companion Repository

```bash
# List all files in companion repo
ls -laR D:/repos/gh/disler/{repo-name}/

# Read key files:
# - README.md (overview)
# - CLAUDE.md (if exists - critical for understanding agentic patterns)
# - Any .claude/ directory contents
# - Source code demonstrating lesson concepts
```markdown

#### Step 1.3: Document Key Takeaways

Create analysis notes covering:

- **Core Tactic**: The main principle taught
- **Frameworks/Acronyms**: Any named frameworks (PITER, ADW, ZTE, etc.)
- **Implementation Patterns**: How the concept is applied in code
- **Anti-Patterns**: What to avoid
- **Metrics/KPIs**: How to measure success

### Phase 2: Component Extraction

#### Step 2.1: Identify Potential Components

For each lesson, evaluate what Claude Code components could embody the teaching:

| Component Type | When to Use | Examples |
| -------------- | ----------- | -------- |
| **Skill** | Reusable workflow/capability with clear trigger keywords | `context-priming`, `feedback-loop-design` |
| **Subagent** | Specialized agent for specific task delegation | `review-agent`, `documentation-agent` |
| **Command** | User-invoked action with specific outcome | `/prime-context`, `/run-piter` |
| **Memory File** | Static rules/principles to always load | `agentic-kpis.md`, `leverage-points.md` |
| **Hook** | Automated behavior on events | Pre-commit validation, context measurement |

#### Step 2.2: Validate Against Official Docs

Before building any component, invoke relevant skills:

```text
# For skills
Invoke skill: skill-development

# For subagents
Invoke skill: subagent-development

# For commands
Invoke skill: command-development

# For memory/CLAUDE.md patterns
Invoke skill: memory-management

# For hooks
Invoke skill: hook-management
```yaml

**CRITICAL**: Reference `analysis/DOCUMENTATION_AUDIT.md` for:

- Skill naming conventions (avoid cryptic acronyms)
- Subagent architectural constraints (cannot spawn other subagents)
- Command naming conventions (kebab-case required)
- `allowed-tools` syntax (comma-separated, not arrays)
- Model ID standards (`claude-opus-4-5-20251101`, `claude-sonnet-4-5-20250929`)

#### Step 2.3: Map Lesson to Components

Create a mapping table:

| Lesson Concept | Component Type | Component Name | Purpose |
| -------------- | -------------- | -------------- | ------- |
| Example: PITER Framework | Skill | `piter-workflow` | Guide AFK agent setup |
| Example: Context Priming | Command | `/prime` | Load task-specific context |

### Phase 3: Implementation

#### Step 3.1: Create Component Scaffolds

Use official patterns from docs-management skill:

- Skills: YAML frontmatter + markdown body
- Subagents: Agent file with tools/model configuration
- Commands: Markdown with optional frontmatter
- Memory: Structured markdown following CLAUDE.md conventions

#### Step 3.2: Cross-Reference Existing Components

Check if similar components exist in:

- `plugins/claude-ecosystem/` - Official patterns
- `plugins/code-quality/` - Quality-focused patterns
- `plugins/google-ecosystem/` - Multi-tool patterns

#### Step 3.3: Build and Test

1. Create component in appropriate location
2. Test with sample prompts
3. Validate behavior matches lesson intent
4. Document usage examples

### Phase 4: Documentation

#### Step 4.1: Update Plugin Manifest

Add new components to `plugin.json`:

```json
{
  "skills": [...],
  "agents": [...],
  "commands": [...],
  "hooks": [...]
}
```markdown

#### Step 4.2: Create Component Documentation

Each component should have:

- Clear description of purpose
- Link back to source lesson
- Usage examples
- Related components

## Lesson-Specific Analysis Template

Use this template for each lesson analysis:

```markdown
# Lesson N Analysis: {Title}

## Content Summary

### Core Tactic
{One-sentence summary of the main teaching}

### Key Frameworks
- {Framework 1}: {Description}
- {Framework 2}: {Description}

### Implementation Patterns from Repo
- {Pattern 1}
- {Pattern 2}

## Extracted Components

### Skills
| Name | Purpose | Keywords |
| ---- | ------- | -------- |

### Subagents
| Name | Purpose | Tools |
| ---- | ------- | ----- |

### Commands
| Name | Purpose | Arguments |
| ---- | ------- | --------- |

### Memory Files
| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |

## Validation Checklist
- [ ] Reviewed against official docs - See DOCUMENTATION_AUDIT.md
- [ ] No duplication with existing components
- [ ] Follows plugin conventions
- [ ] Model IDs use correct format (claude-opus-4-5-20251101, claude-sonnet-4-5-20250929)
- [ ] Tested with sample prompts
```markdown

## Lesson Mapping Overview

| Lesson | Title | Primary Focus | Expected Components |
| ------ | ----- | ------------- | ------------------- |
| 1 | Hello Agentic Coding | Stop coding, let agents work | Philosophy/principles memory |
| 2 | 12 Leverage Points | Adopt agent's perspective | Leverage points checklist |
| 3 | Success is Planned | Template engineering | Plan templates, meta-prompts |
| 4 | AFK Agents | PITER framework, out-of-loop | PITER skill/workflow |
| 5 | Close the Loops | Feedback loops, validation | Feedback loop patterns |
| 6 | Let Your Agents Focus | One agent, one purpose | Specialized agent patterns |
| 7 | ZTE Secret | Zero-touch engineering | ZTE workflow skill |
| 8 | The Agentic Layer | Prioritize agentics | Agentic layer structure |
| 9 | Elite Context Engineering | R&D framework, context management | Context engineering skill |
| 10 | Agentic Prompt Engineering | 7 levels of prompts | Prompt level templates |
| 11 | Building Domain-Specific Agents | Custom agents, SDK | Agent building patterns |
| 12 | Multi-Agent Orchestration | Fleet management, PETER | Orchestration patterns |

## Quality Gates

Before finalizing any lesson analysis:

1. **Completeness**: All lesson files read and understood
2. **Repo Analysis**: All companion repo files examined
3. **Doc Validation**: Official docs consulted for each component type
4. **No Duplication**: Components don't duplicate existing functionality
5. **Actionable**: Components provide real value, not just documentation

## Output Location

All analysis artifacts go in:

```text
plugins/tac/
  analysis/
    lesson-001-analysis.md
    lesson-002-analysis.md
    ...
  skills/
    {skill-name}/
      SKILL.md
  agents/
    {agent-name}.md
  commands/
    {command-name}.md
  memory/
    {memory-file}.md
```yaml

---

**Last Updated:** 2025-12-04
