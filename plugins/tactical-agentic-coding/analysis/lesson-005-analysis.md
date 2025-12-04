# Lesson 5 Analysis: Close The Loops - More Compute, More Confidence

## Content Summary

### Core Tactic

**Always Add Feedback Loops** - Your work is useless unless it's tested. By teaching your agents to test through linters, unit tests, UI tests, and end-to-end validation, you create closed-loop systems where agents self-validate their work and continue building until the feedback is positive.

### Key Frameworks

#### Closed Loop Prompt Structure

Every closed loop prompt has three parts:

| Part | Purpose | Example |
| --- | --- | --- |
| **Request** | What needs to be done | "Update the SQL processor" |
| **Validate** | How to verify success | "Run: ruff check, pytest, python compile" |
| **Resolve** | What to do if validation fails | "If errors, fix and rerun all validation steps" |

#### The Core Validation Question

> "Given a unit of valuable work that's production ready, how would you, the engineer, test and validate this work?"

If you can answer this for every class of work and encode it into commands or tool calls, you will fly while other engineers run.

#### Testing Types for Closed Loops

| Type | Command | Purpose |
| --- | --- | --- |
| **Linting** | `ruff check .` | Code quality, unused imports |
| **Unit Tests** | `pytest tests/` | Function-level validation |
| **Type Check** | `tsc --noEmit` | TypeScript type correctness |
| **Build** | `bun run build` | Production compilation |
| **E2E Tests** | Playwright browser automation | Full user flow validation |
| **API Health** | Custom health checks | Service availability |

### Implementation Patterns from Repo (tac-5)

1. **Test Command** (`/test`) - Comprehensive validation suite:

   ```text
   # Application Validation Test Suite
   Execute comprehensive validation tests for both frontend and backend components,
   returning results in a standardized JSON format for automated processing.

   ## Test Execution Sequence
   ### Backend Tests
   1. Python Syntax Check
   2. Backend Code Quality Check (ruff)
   3. All Backend Tests (pytest)

   ### Frontend Tests
   4. TypeScript Type Check
   5. Frontend Build

   ## Report
   Return results exclusively as a JSON array based on Output Structure
   ```

2. **E2E Test Command** (`/test_e2e`) - Browser automation with Playwright:

   ```text
   Execute end-to-end (E2E) tests using Playwright browser automation (MCP Server).

   ## Instructions
   - Read the `e2e_test_file`
   - Execute the `Test Steps` using Playwright browser automation
   - Review the `Success Criteria` and if any fail, mark test as failed
   - Capture screenshots as specified
   - Return results in the format requested
   ```

3. **E2E Test Files** - User story format:

   ```text
   # E2E Test: Basic Query Execution

   ## User Story
   As a user
   I want to query my data using natural language
   So that I can access information without writing SQL

   ## Test Steps
   1. Navigate to the Application URL
   2. Take a screenshot of the initial state
   3. **Verify** the page title is "Natural Language SQL Interface"
   ...

   ## Success Criteria
   - Query input accepts text
   - Results display correctly
   ```

4. **Resolve Failed Test** (`/resolve_failed_test`):

   ```text
   Fix a specific failing test using the provided failure details.

   ## Instructions
   1. Analyze the Test Failure
   2. Context Discovery (git diff, specs)
   3. Reproduce the Failure
   4. Fix the Issue (minimal, targeted)
   5. Validate the Fix
   ```

5. **ADW Test Workflow** (`adw_test.py`):
   - Runs complete test suite
   - Loops through failed tests
   - Spawns individual resolver agents per failure
   - Retries up to MAX_TEST_RETRY_ATTEMPTS (4)
   - E2E tests have separate MAX_E2E_TEST_RETRY_ATTEMPTS (2)

### JSON Output Pattern

Tests return structured JSON for automation:

```json
[
  {
    "test_name": "frontend_build",
    "passed": false,
    "execution_command": "cd app/client && bun run build",
    "test_purpose": "Validates TypeScript compilation",
    "error": "TS2345: Argument of type 'string' is not assignable"
  }
]
```

This enables downstream agents to pick up specific failures and resolve them.

### Anti-Patterns Identified

- **Manual browser testing**: "Opening the browser and clicking through your new feature is a waste of time"
- **Missing feedback loops**: Agents running loose without validation
- **Tests modifying production data**: Tests should run in isolation
- **Single validation**: Not rerunning all validation steps after a fix
- **Untested code**: "Your work is useless unless it's tested"

### Metrics/KPIs

Connects back to core KPIs:

- **Presence: DOWN** - Closed loops reduce human intervention
- **Streak: UP** - Self-validating loops produce consistent results
- **Attempts: DOWN** - Agents fix issues before reporting completion
- **Size: UP** - More testing = more confident larger changes

### Key Insight: Test Value Multiplication

> "The value of tests are multiplied by the number of agent executions that occur in your codebase."

Tests are one of the highest through-agent leverage points because they let agents self-validate.

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| --- | --- | --- |
| `closed-loop-design` | Design closed loop prompts | closed loop, validate, feedback, test |
| `test-suite-setup` | Configure comprehensive test suites | test, pytest, ruff, typescript, playwright |
| `e2e-test-design` | Create end-to-end test scenarios | e2e, playwright, browser, user story |

### Subagents

| Name | Purpose | Tools |
| --- | --- | --- |
| `test-runner` | Execute comprehensive test suites | Read, Bash, Glob |
| `e2e-test-runner` | Run Playwright browser tests | Read, Bash, MCP (Playwright) |
| `test-resolver` | Fix specific failing tests | Read, Write, Edit, Bash |
| `e2e-test-resolver` | Fix failing E2E tests | Read, Write, Edit, Bash, MCP (Playwright) |

### Commands

| Name | Purpose | Arguments |
| --- | --- | --- |
| `/test` | Run comprehensive test suite | None |
| `/test_e2e` | Run E2E tests with Playwright | `$1` adw_id, `$2` agent_name, `$3` test_file, `$4` url |
| `/resolve_failed_test` | Fix specific failing test | `$ARGUMENTS` - test failure JSON |
| `/resolve_failed_e2e_test` | Fix failing E2E test | `$ARGUMENTS` - E2E failure JSON |

### Memory Files

| Name | Purpose | Load Condition |
| --- | --- | --- |
| `closed-loop-anatomy.md` | Request-Validate-Resolve structure | When designing validation |
| `test-leverage-point.md` | Why testing multiplies agent value | When explaining testing importance |
| `validation-commands.md` | Standard validation command reference | When adding tests to templates |
| `e2e-test-patterns.md` | E2E test structure and user stories | When creating browser tests |

## Key Insights for Plugin Development

### High-Value Components from Lesson 5

1. **Skill: `closed-loop-design`**
   - Guide creation of self-validating prompts
   - Request-Validate-Resolve pattern
   - Common validation command templates

2. **Memory File: `closed-loop-anatomy.md`**
   - Three-part structure explanation
   - Examples for different test types
   - Resolution instructions pattern

3. **Memory File: `validation-commands.md`**
   - Backend: ruff, pytest, py_compile
   - Frontend: tsc, bun build, vite
   - E2E: Playwright MCP server patterns

4. **Command Templates for Testing**
   - `/test` - Comprehensive test runner
   - `/test_e2e` - Browser automation runner
   - `/resolve_failed_test` - Targeted fixer

### Test Integration in Templates

The lesson shows how to embed testing into meta-prompts:

```bash
## Validation Commands
- `cd app/server && uv run ruff check .`
- `cd app/server && uv run pytest tests/ -v`
- `cd app/client && bun tsc --noEmit`
- `cd app/client && bun run build`
```

And E2E test generation in bug/feature templates:

```text
## End-to-End Test (if applicable)
If this bug affects UI or user interactions, create an end-to-end test...
```

### ADW Test Architecture

```python
adw_test.py
  -> run_tests() # Execute /test command
  -> parse_results() # JSON parsing
  -> for failed_test in failed_tests:
       -> resolve_failed_test() # Spawn resolver agent
       -> rerun_validation() # Confirm fix
  -> run_e2e_tests() # Execute /test_e2e for each e2e file
  -> for failed_e2e in failed_e2e_tests:
       -> resolve_failed_e2e_test() # Spawn E2E resolver
  -> finalize_git_operations() # Commit, push, PR
```

### Key Quotes

> "Test, let your agents scale your success."
>
> "Now engineers that test with their agents win. Full stop, zero exceptions."
>
> "Your work, my work, any engineer's work is useless unless it's tested."
>
> "The next best test used to be you. Now, the next best test is an army of agents validating your entire codebase."
>
> "When you close the loop, you let the code write itself."
>
> "What's more important, the code or your tests? The answer should be your tests."

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript - 53:53 of content!)
- [x] Explored tac-5 repository structure
- [x] Read .claude/commands/test.md (test suite runner)
- [x] Read .claude/commands/test_e2e.md (E2E test runner)
- [x] Read .claude/commands/resolve_failed_test.md (test resolver)
- [x] Read .claude/commands/e2e/test_basic_query.md (E2E test example)
- [x] Read adws/adw_test.py (ADW test workflow)
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Builds on Lesson 2**: Tests as highest through-agent leverage point
- **Builds on Lesson 3**: Validation commands embedded in templates
- **Builds on Lesson 4**: PITER framework for out-loop testing
- **Sets up Lesson 6**: Specialized agents (test runner, resolver)
- **Sets up Lesson 7**: Zero Touch Engineering through self-validation

## Notable Implementation Details

### JSON Structured Output for Agent Chaining

Tests return JSON that downstream agents can parse and act on:

```json
{
  "test_name": "string",
  "passed": boolean,
  "execution_command": "string",
  "test_purpose": "string",
  "error": "optional string"
}
```

This enables the ADW to spawn targeted resolver agents with exact context.

### E2E Test Screenshot Pattern

```text
agents/<adw_id>/<agent_name>/img/<test_name>/
  01_initial_state.png
  02_query_entered.png
  03_results_displayed.png
```

Screenshots provide visual evidence and debugging context.

### Retry Strategy

- Unit tests: MAX_TEST_RETRY_ATTEMPTS = 4
- E2E tests: MAX_E2E_TEST_RETRY_ATTEMPTS = 2

E2E tests are more expensive (browser automation), so fewer retries.

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
