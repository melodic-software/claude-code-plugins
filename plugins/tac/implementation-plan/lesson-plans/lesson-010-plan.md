# Lesson 010: Agentic Prompt Engineering - Implementation Plan

## Lesson Overview

**Title:** Agentic Prompt Engineering
**Core Tactic:** Master Agentic Prompt Engineering - The Seven Levels
**Key Insight:** "The prompt is now the fundamental unit of engineering. Every prompt you create becomes a force multiplier."

## Source Materials Validated

- [x] lesson-010-analysis.md - Comprehensive analysis with seven levels, sections, stakeholder trifecta
- [x] lesson.md - Core concepts: Seven Levels, 80/20 Rule, Stakeholder Trifecta
- [x] agentic-prompt-engineering repo - Explored commands, agents, output styles, patterns

## Components to Create

### Memory Files (5 files)

| File | Purpose | Source |
| ------ | --------- | -------- |
| `seven-levels.md` | The seven levels of agentic prompts with examples | Core lesson framework |
| `prompt-sections-reference.md` | Composable prompt sections with tier rankings | Analysis sections reference |
| `stakeholder-trifecta.md` | Engineering for you, your team, and your agents | Lesson key concept |
| `system-vs-user-prompts.md` | Distinction and best practices | Analysis system prompt architecture |
| `variable-patterns.md` | Dynamic vs static variables, naming conventions | Repo variable patterns |

### Skills (4 skills)

| Skill | Purpose | Tools |
| ------- | --------- | ------- |
| `prompt-level-selection` | Guide selection of appropriate prompt level for task | Read, Grep, Glob |
| `prompt-section-design` | Design composable prompt sections | Read, Grep, Glob |
| `template-meta-prompt-creation` | Create prompts that generate prompts (Level 6) | Read, Grep, Glob |
| `system-prompt-engineering` | Design effective system prompts for custom agents | Read, Grep, Glob |

### Commands (4 commands)

| Command | Purpose | Arguments |
| --------- | --------- | ----------- |
| `create-prompt` | Generate a new prompt at specified level | `$1` - level, `$ARGUMENTS` - description |
| `analyze-prompt` | Analyze existing prompt and suggest improvements | `$1` - path to prompt file |
| `upgrade-prompt` | Upgrade prompt to next level | `$1` - path to prompt, `$2` - target level |
| `list-prompt-levels` | Show the seven levels with quick reference | None |

### Agents (3 agents)

| Agent | Purpose | Tools | Model |
| ------- | --------- | ------- | ------- |
| `prompt-analyzer` | Analyze and classify existing prompts | Read, Grep, Glob | haiku |
| `prompt-generator` | Generate prompts from specifications | Read, Write | sonnet |
| `workflow-designer` | Design workflow sections for prompts | Read, Write | sonnet |

## Component Specifications

### Memory File: seven-levels.md

**Content Outline:**

- Level 1: High-Level Prompt
  - Simple reusable static prompt
  - 1-3 sections: Title, High-level prompt
  - Use case: One-off repeatable tasks
- Level 2: Workflow Prompt (Game Changer)
  - Sequential task list
  - S-tier Workflow section
  - Input -> Workflow -> Output pattern
- Level 3: Control Flow
  - Conditional logic, branching, loops
  - `<loop-tags>` for iteration
  - STOP conditions for early exit
- Level 4: Delegation Prompt
  - Kicks off other workflows
  - Task tool integration
  - Parallel agent launching
- Level 5: Higher Order Prompts
  - Prompts passing prompts
  - Accepts prompt file as input
  - Scaffold top-level structure
- Level 6: Template Meta Prompt
  - Prompts that generate prompts
  - Highest leverage
  - Includes Specified Format template
- Level 7: Self-Improving Prompt
  - Self-modifying systems
  - Expertise section evolves
  - Plan-Build-Improve pattern
- The 80/20 Rule: Levels 3-4 cover 80% of use cases

### Memory File: prompt-sections-reference.md

**Content Outline:**

- S-Tier Usefulness: Workflow
- A-Tier: Variables, Examples, Control Flow, Delegation, Template
- B-Tier: Purpose, High-Level, Higher Order, Instructions
- C-Tier: Metadata, Codebase Structure, Relevant Files, Report
- Section definitions and when to use each
- Section structure examples

### Memory File: stakeholder-trifecta.md

**Content Outline:**

- The Three Stakeholders:
  1. You - Quick understanding, future reference
  2. Your Team - Consistent format, clear purpose
  3. Your Agents - Direct language, precise instructions
- Communication focus for each
- Consistency as weapon against confusion
- Agentic shift most engineers haven't made

### Memory File: system-vs-user-prompts.md

**Content Outline:**

- System Prompt characteristics:
  - Rules for all conversations
  - Runs once, affects everything
  - Orders of magnitude more important
  - Best for: Custom agents
- User Prompt characteristics:
  - Single task
  - Runs per request
  - Lower blast radius
  - Best for: Reusable slash commands
- When to use each
- System prompt architecture (Purpose, Instructions, Examples)

### Memory File: variable-patterns.md

**Content Outline:**

- Dynamic Variables:
  - `$1`, `$2`, `$3` - Position-based
  - `$ARGUMENTS` - All arguments as string
- Static Variables:
  - Defined in Variables section
  - Fixed values, paths, defaults
- Naming Convention:
  - SCREAMING_SNAKE_CASE
  - Dynamic first, then static
- Reference patterns in workflow
- Default value syntax: `$2 or 3 if not provided`

### Skill: prompt-level-selection

**Purpose:** Guide selection of appropriate prompt level for a task.

**Workflow:**

1. Understand the task requirements
2. Check complexity indicators
3. Match to appropriate level
4. Recommend level with rationale
5. Note: 80/20 rule - Levels 3-4 cover most cases

**Decision Tree:**

- Simple repeatable? -> Level 1
- Sequential workflow? -> Level 2
- Conditionals/loops? -> Level 3
- Delegating work? -> Level 4
- Processing other prompts? -> Level 5
- Creating prompts? -> Level 6
- Self-evolving? -> Level 7

### Skill: prompt-section-design

**Purpose:** Design composable prompt sections for a prompt.

**Workflow:**

1. Identify prompt purpose
2. Determine required sections (Workflow is S-tier)
3. Design Variables section (dynamic + static)
4. Design Workflow section (numbered steps)
5. Add optional sections as needed
6. Structure Report section

### Skill: template-meta-prompt-creation

**Purpose:** Create Level 6 template meta-prompts.

**Workflow:**

1. Identify target prompt pattern
2. Design Specified Format template
3. Create meta-prompt structure
4. Add documentation fetching (optional)
5. Include Task parallelization (optional)
6. Output to appropriate location

### Skill: system-prompt-engineering

**Purpose:** Design effective system prompts for custom agents.

**Workflow:**

1. Define agent's purpose and domain
2. Design Purpose section (direct, clear)
3. Design Instructions section (rules, constraints)
4. Create Examples section (critical for behavior)
5. Avoid prescriptive workflows (reduces agency)
6. Output agent definition

### Command: create-prompt

**Purpose:** Generate a new prompt at specified level.

**Arguments:**

- `$1`: Level (1-7)
- `$ARGUMENTS`: High-level description of prompt

**Implementation:**

- Invoke @prompt-level-selection skill for guidance
- Generate prompt structure for specified level
- Include appropriate sections
- Save to .claude/commands/

### Command: analyze-prompt

**Purpose:** Analyze existing prompt and suggest improvements.

**Arguments:**

- `$1`: Path to prompt file

**Implementation:**

- Read the prompt file
- Classify current level
- Identify sections used
- Suggest improvements
- Recommend level upgrades if appropriate

### Command: upgrade-prompt

**Purpose:** Upgrade prompt to next level.

**Arguments:**

- `$1`: Path to prompt file
- `$2`: Target level (optional, defaults to current + 1)

**Implementation:**

- Read current prompt
- Analyze structure
- Add sections needed for target level
- Transform workflow for new capabilities

### Command: list-prompt-levels

**Purpose:** Quick reference for the seven levels.

**Implementation:**

- Display the seven levels with brief descriptions
- Note the 80/20 rule
- Reference @seven-levels.md for details

### Agent: prompt-analyzer

**Purpose:** Analyze and classify existing prompts.

**Configuration:**

- Model: haiku (fast classification)
- Tools: Read, Grep, Glob (read-only)

**Output:** JSON with level classification, sections found, improvement suggestions.

### Agent: prompt-generator

**Purpose:** Generate prompts from specifications.

**Configuration:**

- Model: sonnet (creative generation)
- Tools: Read, Write

**Output:** Complete prompt file at specified level.

### Agent: workflow-designer

**Purpose:** Design workflow sections for prompts.

**Configuration:**

- Model: sonnet (structured design)
- Tools: Read, Write

**Output:** Workflow section with numbered steps, control flow, delegation.

## Implementation Order

1. Create memory files (foundational knowledge)
   - seven-levels.md
   - prompt-sections-reference.md
   - stakeholder-trifecta.md
   - system-vs-user-prompts.md
   - variable-patterns.md

2. Create skills (workflows for prompt engineering)
   - prompt-level-selection
   - prompt-section-design
   - template-meta-prompt-creation
   - system-prompt-engineering

3. Create commands (user-facing operations)
   - create-prompt
   - analyze-prompt
   - upgrade-prompt
   - list-prompt-levels

4. Create agents (specialized workers)
   - prompt-analyzer
   - prompt-generator
   - workflow-designer

5. Update plugin.json

## Validation Criteria

- [ ] Memory files explain seven levels clearly
- [ ] Skills provide actionable prompt engineering workflows
- [ ] Commands enable practical prompt creation/analysis
- [ ] Agents follow one-agent-one-purpose principle
- [ ] All naming follows kebab-case convention
- [ ] Skills use `allowed-tools` as comma-separated string
- [ ] Agents use `tools` as array
- [ ] No duplicates with existing plugin components

## Cross-References

- **Lesson 003**: Templates -> Meta-prompts
- **Lesson 006**: One agent, one prompt, one purpose
- **Lesson 008**: Agentic layer -> prompt libraries
- **Lesson 009**: Context engineering -> prompt efficiency

## Notes

- The seven levels framework is the core organizing principle
- 80/20 rule is crucial: Levels 3-4 cover 80% of practical use cases
- Stakeholder trifecta is a key mindset shift for agentic engineering
- Output styles from repo are valuable but already covered in context priming patterns

---

**Plan Created:** 2025-12-04
**Status:** Ready for Implementation
