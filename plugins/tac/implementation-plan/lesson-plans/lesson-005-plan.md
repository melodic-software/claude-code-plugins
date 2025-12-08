# Lesson 005 Plan: Close the Loops

**Created:** 2025-12-04
**Status:** Planning Complete
**Lesson:** Close the Loops - Always Add Feedback Loops

---

## Source Material Validated

- [x] Lesson content at `plugins/tac/lessons/lesson-005-close-the-loops/`
- [x] Analysis at `plugins/tac/analysis/lesson-005-analysis.md`
- [x] Companion repo explored at `D:\repos\gh\disler\tac-5`
- [x] Official Claude Code hooks/commands docs validated

## Core Concepts from Lesson

### Core Tactic: Always Add Feedback Loops

The #1 way to get more reliable agents: Add feedback loops. Every agentic operation should have a validation step that feeds back into resolution.

### Closed Loop Prompt Structure

```text
REQUEST → VALIDATE → RESOLVE
    ↑                    ↓
    └────────────────────┘
```markdown

1. **Request**: Ask the agent to perform a task
2. **Validate**: Check if the task succeeded (run tests, verify output)
3. **Resolve**: If validation fails, fix issues and re-validate

### Key Patterns from tac-5

1. **/test command**: Run test suite → Return JSON with pass/fail + execution_command
2. **/test-e2e command**: Execute E2E test with Playwright → Verify Success Criteria
3. **/resolve-failed-test**: Take failed test JSON → Reproduce → Fix → Re-validate
4. **/resolve-failed-e2e-test**: Take failed E2E result → Fix → Re-test

### Validation Command Pattern

Every plan includes validation commands:

```markdown
## Validation Commands
Execute every command to validate with 100% confidence and zero regressions

- cd app/server && uv run pytest
- cd app/client && bun tsc --noEmit
- cd app/client && bun run build
```yaml

---

## Components to Create

### Memory Files (4 files)

Location: `plugins/tac/memory/`

| File | Purpose | Source |
| ------ | --------- | -------- |
| `closed-loop-anatomy.md` | Request-Validate-Resolve structure with examples | Lesson transcript |
| `test-leverage-point.md` | Tests as the ultimate leverage point in feedback loops | Lesson analysis |
| `validation-commands.md` | Patterns for adding validation commands to plans | tac-5 patterns |
| `e2e-test-patterns.md` | E2E testing with Playwright and screenshot validation | tac-5/commands/e2e/ |

### Skills (3 skills)

Location: `plugins/tac/skills/`

| Skill | Purpose | Tools |
| ------- | --------- | ------- |
| `closed-loop-design` | Design closed-loop prompts with Request-Validate-Resolve | Read, Grep, Glob |
| `test-suite-setup` | Set up test validation commands for any project | Read, Bash |
| `e2e-test-design` | Design E2E tests with Playwright patterns | Read, Grep |

### Commands (4 commands)

Location: `plugins/tac/commands/`

| Command | Purpose | Pattern |
| --------- | --------- | --------- |
| `test.md` | Run project test suite, return JSON results | Request phase |
| `test-e2e.md` | Run E2E test specification | Request phase |
| `resolve-failed-test.md` | Fix failed test and re-validate | Resolve phase |
| `resolve-failed-e2e-test.md` | Fix failed E2E test and re-validate | Resolve phase |

### Agents (4 agents)

Location: `plugins/tac/agents/`

| Agent | Purpose | Model | Tools |
| ------- | --------- | ------- | ------- |
| `test-runner.md` | Execute unit/integration tests, report JSON | haiku | Bash, Read |
| `e2e-test-runner.md` | Execute E2E tests with browser | sonnet | Bash, Read |
| `test-resolver.md` | Analyze and fix failed tests | sonnet | Read, Write, Edit, Bash |
| `e2e-test-resolver.md` | Analyze and fix failed E2E tests | sonnet | Read, Write, Edit, Bash |

---

## Implementation Order

### Phase 1: Memory Files

1. Create `memory/closed-loop-anatomy.md`
2. Create `memory/test-leverage-point.md`
3. Create `memory/validation-commands.md`
4. Create `memory/e2e-test-patterns.md`

### Phase 2: Skills

1. Create `skills/closed-loop-design/SKILL.md`
2. Create `skills/test-suite-setup/SKILL.md`
3. Create `skills/e2e-test-design/SKILL.md`

### Phase 3: Commands

1. Create `commands/test.md`
2. Create `commands/test-e2e.md`
3. Create `commands/resolve-failed-test.md`
4. Create `commands/resolve-failed-e2e-test.md`

### Phase 4: Agents

1. Create `agents/test-runner.md`
2. Create `agents/e2e-test-runner.md`
3. Create `agents/test-resolver.md`
4. Create `agents/e2e-test-resolver.md`

### Phase 5: Registration

1. Update `plugin.json` with new components

---

## Content Specifications

### Memory: closed-loop-anatomy.md

**Content outline:**

- Definition: Feedback loop = mechanism ensuring agent output meets requirements
- The three phases: Request, Validate, Resolve
- Why closed loops matter (reliability, self-correction, reduced human intervention)
- Pattern template:

  ```text
  1. REQUEST: [Task description]
  2. VALIDATE: [How to verify success]
  3. RESOLVE: [What to do if validation fails]
  ```

- Examples: Test-driven, E2E, linting, type checking

### Memory: test-leverage-point.md

**Content outline:**

- Tests as the #1 leverage point for feedback loops
- Why tests: deterministic, fast, automatable
- Test types as validation mechanisms:
  - Unit tests: Function-level correctness
  - Integration tests: Component interaction
  - E2E tests: User journey validation
- Adding tests to existing codebases
- Test output as structured data for resolution

### Memory: validation-commands.md

**Content outline:**

- Standard validation commands pattern
- Project-agnostic template:

  ```markdown
  ## Validation Commands
  Execute every command to validate with 100% confidence

  - [linting command]
  - [type check command]
  - [unit test command]
  - [build command]
  ```

- Common validation commands by technology stack
- Validation command discovery workflow

### Memory: e2e-test-patterns.md

**Content outline:**

- E2E test specification format
- User story driven testing
- Test Steps with **Verify** checkpoints
- Success Criteria checklist
- Screenshot capture for evidence
- JSON output format for automation

### Skill: closed-loop-design

**Purpose:** Guide users in designing closed-loop prompts

**Workflow:**

1. Identify the operation (what task needs validation?)
2. Define the validation mechanism (tests, linting, manual)
3. Design the resolve path (what happens on failure?)
4. Create the prompt structure

### Skill: test-suite-setup

**Purpose:** Help set up test validation for any project

**Workflow:**

1. Detect project type (Python, TypeScript, etc.)
2. Identify existing test infrastructure
3. Generate validation commands
4. Create test command template

### Skill: e2e-test-design

**Purpose:** Design E2E tests following tac-5 patterns

**Workflow:**

1. Define user story
2. Create test steps with verify points
3. Define success criteria
4. Generate test specification file

### Command: test.md

**Pattern from tac-5:**

```markdown
# Application Validation Test Suite

## Instructions
- Execute each test in sequence
- Capture result (passed/failed) and error messages
- Return ONLY JSON array with test results
- If a test fails, stop and return results thus far

## Output Format
[
  {
    "test_name": "...",
    "passed": true/false,
    "execution_command": "...",
    "test_purpose": "...",
    "error": null or "..."
  }
]
```markdown

### Command: test-e2e.md

**Pattern from tac-5:**

```markdown
# E2E Test Runner

## Variables
e2e_test_file: $1

## Instructions
- Read the e2e_test_file
- Execute Test Steps
- Review Success Criteria
- Capture screenshots as specified

## Output Format
{
  "test_name": "...",
  "status": "passed|failed",
  "screenshots": [...],
  "error": null or "..."
}
```markdown

### Command: resolve-failed-test.md

**Pattern from tac-5:**

```markdown
# Resolve Failed Test

## Instructions

1. Analyze the Test Failure
   - Review test name, purpose, error message
   - Identify root cause

2. Reproduce the Failure
   - Use execution_command from test data

3. Fix the Issue
   - Make minimal, targeted changes

4. Validate the Fix
   - Re-run same execution_command
   - Confirm test now passes
```yaml

### Command: resolve-failed-e2e-test.md

Similar to resolve-failed-test but for E2E context.

### Agents

All agents follow the pattern established in Lesson 004:

- Clear role in pipeline
- Specific tool access
- Appropriate model selection (haiku for fast/simple, sonnet for reasoning)
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
| `memory/closed-loop-anatomy.md` | CREATE |
| `memory/test-leverage-point.md` | CREATE |
| `memory/validation-commands.md` | CREATE |
| `memory/e2e-test-patterns.md` | CREATE |
| `skills/closed-loop-design/SKILL.md` | CREATE |
| `skills/test-suite-setup/SKILL.md` | CREATE |
| `skills/e2e-test-design/SKILL.md` | CREATE |
| `commands/test.md` | CREATE |
| `commands/test-e2e.md` | CREATE |
| `commands/resolve-failed-test.md` | CREATE |
| `commands/resolve-failed-e2e-test.md` | CREATE |
| `agents/test-runner.md` | CREATE |
| `agents/e2e-test-runner.md` | CREATE |
| `agents/test-resolver.md` | CREATE |
| `agents/e2e-test-resolver.md` | CREATE |
| `.claude-plugin/plugin.json` | UPDATE |
| `implementation-plan/MASTER-TRACKER.md` | UPDATE |

---

## Key Transformations

| tac-5 Pattern | Plugin Implementation |
| --------------- | ---------------------- |
| `/test` command | `commands/test.md` |
| `/test_e2e` command | `commands/test-e2e.md` (kebab-case) |
| `/resolve_failed_test` | `commands/resolve-failed-test.md` (kebab-case) |
| `/resolve_failed_e2e_test` | `commands/resolve-failed-e2e-test.md` (kebab-case) |
| Python ADW scripts | Reference patterns in memory files (project-specific) |
| Hooks (pre_tool_use, etc.) | Reference patterns only (project-specific) |

---

## Notes

- Hooks from tac-5 are project-specific automation (not portable as plugin)
- ADW Python scripts are project-specific orchestration
- Focus on the portable patterns: closed-loop structure, validation commands, test/resolve workflow
- Commands use kebab-case (not underscores from tac-5)
