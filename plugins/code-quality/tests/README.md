# Code Quality Plugin Tests

This directory contains tests for the code-quality plugin hooks and skills.

## Test Structure

```text
tests/
├── hooks/
│   └── markdown-lint/
│       ├── integration.test.sh      # Integration tests for hook
│       ├── test-linting-behavior.sh # Comprehensive behavior tests
│       └── fixtures/
│           ├── test-payloads.json   # Sample JSON payloads for testing
│           ├── fixable.md           # Markdown with fixable errors
│           ├── test-clean.md        # Clean markdown (no errors)
│           └── test-unfixable.md    # Markdown with unfixable errors
└── README.md                        # This file
```

## Running Tests

### Prerequisites

- Bash shell (Git Bash on Windows, native on macOS/Linux)
- `jq` for JSON parsing
- `npx` (Node.js) for markdownlint-cli2

### Running Integration Tests

```bash
# From plugin root
./tests/hooks/markdown-lint/integration.test.sh
```

### Running Behavior Tests

```bash
# From plugin root
./tests/hooks/markdown-lint/test-linting-behavior.sh
```

## Test Fixtures

### test-payloads.json

Contains sample JSON payloads that simulate Claude Code tool invocations:

- `write_markdown_file` - Writing a markdown file
- `edit_markdown_file` - Editing a markdown file
- `write_non_markdown` - Writing a non-markdown file (should be ignored)
- `write_excluded_path` - Writing to excluded path (should be ignored)
- `non_write_edit_tool` - Non-Write/Edit tool (should be ignored)

### Markdown Fixtures

- `fixable.md` - Contains auto-fixable errors (trailing spaces, multiple blanks)
- `test-clean.md` - Clean file with no linting errors
- `test-unfixable.md` - Contains unfixable errors (duplicate h1 headings)

## Writing New Tests

1. Use the test-helpers.sh framework for assertions
2. Follow the existing test structure
3. Test both success and failure cases
4. Clean up any temporary files created during tests
