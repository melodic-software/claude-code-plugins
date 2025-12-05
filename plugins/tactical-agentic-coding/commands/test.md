# Application Validation Test Suite

Run the project's test suite and report results in structured JSON format.

## Purpose

Proactively identify issues in the application before they impact users. This command executes the validation stack and reports results for automated processing.

## Instructions

1. **Detect Project Type**: Look for package.json, pyproject.toml, or other config files
2. **Identify Test Commands**: Find the appropriate test runner and commands
3. **Execute Tests in Sequence**:
   - Lint check
   - Type check (if applicable)
   - Unit/integration tests
   - Build verification
4. **Capture Results**: Record pass/fail status and any error messages
5. **Return JSON**: Output only the structured JSON array

## Test Execution Sequence

Execute each validation command in order:

1. **Lint Check** - Code style and syntax validation
2. **Type Check** - Type safety verification (TypeScript, Python with mypy)
3. **Unit Tests** - Core functionality tests
4. **Build** - Production build verification

**IMPORTANT**: If a test fails, stop processing and return results thus far.

## Output Format

Return ONLY a JSON array with test results:

```json
[
  {
    "test_name": "lint_check",
    "passed": true,
    "execution_command": "npm run lint",
    "test_purpose": "Validates code style and syntax",
    "error": null
  },
  {
    "test_name": "type_check",
    "passed": true,
    "execution_command": "npx tsc --noEmit",
    "test_purpose": "Validates TypeScript types",
    "error": null
  },
  {
    "test_name": "unit_tests",
    "passed": false,
    "execution_command": "npm test",
    "test_purpose": "Validates core functionality",
    "error": "FAIL tests/auth.test.ts - Expected 200, received 401"
  }
]
```

## Result Structure

Each test result includes:

| Field | Description |
| ------- | ------------- |
| `test_name` | Identifier for the test category |
| `passed` | Boolean - true if test passed |
| `execution_command` | Exact command to reproduce |
| `test_purpose` | What this test validates |
| `error` | Error message if failed, null if passed |

## Sorting

Sort the JSON array with failed tests (`passed: false`) at the top.

## Integration with Closed Loop

This command is the **REQUEST** phase of a closed loop:

```text
/test → [JSON results] → /resolve-failed-test {result}
```

The structured output enables automated resolution.
