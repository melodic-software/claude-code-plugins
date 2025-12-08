# Lesson 006 Plan: Let Your Agents Focus

**Created:** 2025-12-04
**Status:** Planning Complete
**Lesson:** Let Your Agents Focus - Agentic Review and Documentation

---

## Source Material Validated

- [x] Lesson content at `plugins/tac/lessons/lesson-006-let-your-agents-focus/`
- [x] Analysis at `plugins/tac/analysis/lesson-006-analysis.md`
- [x] Companion repo explored at `D:\repos\gh\disler\tac-6`
- [x] Official Claude Code docs validated (subagents, commands)

## Core Concepts from Lesson

### Core Tactic: One Agent, One Prompt, One Purpose

Specialized agents with focused prompts to achieve a single purpose well:

- Frees up the context window
- Lets agents focus on what matters most
- Creates reproducible, improvable prompts
- Enables eval creation for the agentic layer

### Three Constraints of Agentic Engineers

1. **Context window** - Limited tokens available
2. **Codebase complexity** - Problem difficulty
3. **Our abilities** - Skill and expertise

Specialized agents bypass TWO of these constraints (context window and abilities).

### Review vs Testing - Critical Distinction

| Aspect | Testing | Review |
| -------- | --------- | -------- |
| Question | Does it work? | Is what we built what we asked for? |
| Focus | Functionality | Alignment with spec |
| Validation | Code execution | Spec comparison |
| Asset | Test results | Screenshots, proof artifacts |

### Minimum Context Principle

> "You want to context engineer as little as possible. You want the minimum context in your prompt required to solve the problem."

### Key Patterns from tac-6

1. **Review Workflow**: Compare implementation against spec with screenshots
2. **Patch Workflow**: Minimal, surgical fixes for blockers
3. **Documentation Workflow**: Generate docs from changes and specs
4. **Conditional Documentation**: Load docs only when conditions match
5. **Issue Severity**: blocker, tech_debt, skippable

---

## Components to Create

### Memory Files (5 files)

Location: `plugins/tac/memory/`

| File | Purpose | Source |
| ------ | --------- | -------- |
| `one-agent-one-purpose.md` | Agent specialization principles | Lesson transcript |
| `minimum-context-principle.md` | Context engineering guidance | Lesson transcript |
| `review-vs-test.md` | Distinction between testing and review | Lesson analysis |
| `conditional-docs-pattern.md` | How to set up conditional loading | tac-6 patterns |
| `issue-severity-classification.md` | blocker, tech_debt, skippable levels | tac-6/review patterns |

### Skills (4 skills)

Location: `plugins/tac/skills/`

| Skill | Purpose | Tools |
| ------- | --------- | ------- |
| `agent-specialization` | Guide creation of focused agents | Read, Grep, Glob |
| `review-workflow-design` | Design review workflows with proof | Read, Grep |
| `conditional-docs-setup` | Set up conditional documentation | Read, Write |
| `patch-design` | Create surgical patch workflows | Read, Grep |

### Commands (3 commands)

Location: `plugins/tac/commands/`

| Command | Purpose | Pattern |
| --------- | --------- | --------- |
| `review.md` | Review implementation against spec | Spec comparison + screenshots |
| `patch.md` | Create minimal targeted fix | Surgical fix planning |
| `document.md` | Generate feature documentation | Doc generation from changes |

### Agents (3 agents)

Location: `plugins/tac/agents/`

| Agent | Purpose | Model | Tools |
| ------- | --------- | ------- | ------- |
| `spec-reviewer.md` | Review implementation against spec | sonnet | Read, Bash, Glob |
| `patch-planner.md` | Create minimal patch plans | sonnet | Read, Write, Glob |
| `documentation-generator.md` | Generate and update docs | sonnet | Read, Write, Glob |

---

## Implementation Order

### Phase 1: Memory Files

1. Create `memory/one-agent-one-purpose.md`
2. Create `memory/minimum-context-principle.md`
3. Create `memory/review-vs-test.md`
4. Create `memory/conditional-docs-pattern.md`
5. Create `memory/issue-severity-classification.md`

### Phase 2: Skills

1. Create `skills/agent-specialization/SKILL.md`
2. Create `skills/review-workflow-design/SKILL.md`
3. Create `skills/conditional-docs-setup/SKILL.md`
4. Create `skills/patch-design/SKILL.md`

### Phase 3: Commands

1. Create `commands/review.md`
2. Create `commands/patch.md`
3. Create `commands/document.md`

### Phase 4: Agents

1. Create `agents/spec-reviewer.md`
2. Create `agents/patch-planner.md`
3. Create `agents/documentation-generator.md`

### Phase 5: Registration

1. Update `plugin.json` with new components

---

## Content Specifications

### Memory: one-agent-one-purpose.md

**Content outline:**

- Core principle: Specialized agents with focused prompts
- Benefits:
  - Full context window for the single task
  - No context confusion from multiple objectives
  - Reproducible and improvable prompts
  - Creates evals for the agentic layer
- Anti-pattern: God model thinking
- Every engineering step needs different context
- Commit and improve your prompts

### Memory: minimum-context-principle.md

**Content outline:**

- Principle: Engineer as little context as possible
- Every piece of context adds variables to reason about
- Context pollution leads to distracted agents
- Just-in-time vs pre-loaded context
- Examples of minimum vs maximum context
- Related to conditional documentation pattern

### Memory: review-vs-test.md

**Content outline:**

- Testing: "Does it work?"
- Review: "Is what we built what we asked for?"
- Different questions require different agents
- Testing validates functionality
- Review validates alignment with spec
- Both are needed in SDLC
- Review captures proof artifacts (screenshots)

### Memory: conditional-docs-pattern.md

**Content outline:**

- Problem: Loading all documentation pollutes context
- Solution: Load docs only when conditions match
- Format:

  ```markdown
  - documentation_path
    - Conditions:
      - When working with X
      - When implementing Y
  ```

- Integration with feature/bug/chore commands
- Keeping conditional docs updated

### Memory: issue-severity-classification.md

**Content outline:**

- Three severity levels:
  - **blocker**: Prevents release, must fix now
  - **tech_debt**: Non-blocking but creates future work
  - **skippable**: Polish items, can ignore
- Only blockers trigger auto-resolution
- Review can succeed with tech_debt/skippable
- Classification guidance

### Skill: agent-specialization

**Purpose:** Guide creation of focused single-purpose agents

**Workflow:**

1. Identify the single purpose
2. Determine minimum required context
3. Select appropriate tools
4. Choose model (haiku/sonnet/opus)
5. Design focused output format

### Skill: review-workflow-design

**Purpose:** Design spec-based review with proof

**Workflow:**

1. Define spec location pattern
2. Design screenshot capture points
3. Define severity classification
4. Set up resolution workflow
5. Configure proof storage

### Skill: conditional-docs-setup

**Purpose:** Set up conditional documentation loading

**Workflow:**

1. Identify documentation files
2. Define loading conditions
3. Create conditional_docs structure
4. Integrate with planning commands
5. Set up update workflow

### Skill: patch-design

**Purpose:** Create surgical patch workflows

**Workflow:**

1. Analyze the specific issue
2. Determine minimum scope
3. Create patch plan
4. Define validation steps
5. Document resolution

### Command: review.md

**Pattern from tac-6:**

```markdown
# Review Implementation Against Spec

## Variables
spec_file: $1

## Instructions
1. Read the specification
2. Analyze git diff against origin/main
3. Take 1-5 screenshots of critical functionality
4. Compare implementation against spec requirements
5. Classify issues: blocker, tech_debt, skippable

## Output Format (JSON)
{
  "success": boolean,
  "review_summary": "string",
  "review_issues": [
    {
      "issue_description": "string",
      "issue_resolution": "string",
      "issue_severity": "blocker| tech_debt |skippable"
    }
  ]
}
```markdown

### Command: patch.md

**Pattern from tac-6:**

```markdown
# Create Focused Patch Plan

## Variables
review_change_request: $1
spec_path: $2 (optional)

## Instructions
This is a PATCH - keep scope MINIMAL.
1. Understand the specific issue
2. Find minimum code changes needed
3. Create surgical patch plan
4. Define validation steps

## Plan Format
- Issue Summary
- Files to Modify (minimal)
- Implementation Steps
- Validation Commands
- Patch Scope (lines, risk, testing)
```markdown

### Command: document.md

**Pattern from tac-6:**

```markdown
# Generate Feature Documentation

## Variables
adw_id: $1
spec_path: $2 (optional)

## Instructions
1. Analyze git diff for changes
2. Read spec if provided
3. Generate documentation following format
4. Create screenshots section
5. Update conditional docs

## Documentation Format
- Overview
- Screenshots
- What Was Built
- Technical Implementation
- How to Use
- Testing
```yaml

### Agents

All agents follow the established patterns:

- Clear single purpose
- Appropriate tool access
- Model selection based on complexity
- Structured output format

---

## Validation Criteria

- [ ] Memory files follow kebab-case naming
- [ ] Skills have YAML frontmatter with `allowed-tools` (comma-separated)
- [ ] Agents have YAML frontmatter with `tools` (array)
- [ ] Commands have `$ARGUMENTS` or `$1`, `$2` for inputs
- [ ] plugin.json updated with all new components
- [ ] No duplicates with existing plugin components

## Files to Create/Modify

| File | Action |
| ------ | -------- |
| `memory/one-agent-one-purpose.md` | CREATE |
| `memory/minimum-context-principle.md` | CREATE |
| `memory/review-vs-test.md` | CREATE |
| `memory/conditional-docs-pattern.md` | CREATE |
| `memory/issue-severity-classification.md` | CREATE |
| `skills/agent-specialization/SKILL.md` | CREATE |
| `skills/review-workflow-design/SKILL.md` | CREATE |
| `skills/conditional-docs-setup/SKILL.md` | CREATE |
| `skills/patch-design/SKILL.md` | CREATE |
| `commands/review.md` | CREATE |
| `commands/patch.md` | CREATE |
| `commands/document.md` | CREATE |
| `agents/spec-reviewer.md` | CREATE |
| `agents/patch-planner.md` | CREATE |
| `agents/documentation-generator.md` | CREATE |
| `.claude-plugin/plugin.json` | UPDATE |
| `implementation-plan/MASTER-TRACKER.md` | UPDATE |

---

## Key Transformations

| tac-6 Pattern | Plugin Implementation |
| --------------- | ---------------------- |
| `/review` command | `commands/review.md` |
| `/patch` command | `commands/patch.md` |
| `/document` command | `commands/document.md` |
| `/conditional_docs` | Memory file pattern (portable) |
| ADW Python scripts | Reference patterns in memory (project-specific) |
| R2 upload | Reference patterns (project-specific infrastructure) |
| Hooks | Reference patterns (project-specific) |

---

## Notes

- R2/S3 upload patterns are project-specific infrastructure (not portable)
- ADW Python orchestration scripts are project-specific
- Conditional docs pattern is portable as a design pattern
- Focus on the portable patterns: review structure, patch workflow, doc generation
- Commands use kebab-case naming
