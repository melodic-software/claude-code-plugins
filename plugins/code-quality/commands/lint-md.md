---
description: Run markdown linting validation on files using markdownlint-cli2
argument-hint: [optional: target files/folders or instructions]
allowed-tools: Read, Bash, Skill
---

# Lint Markdown Command

Run markdown linting validation on all or targeted markdown files using markdownlint-cli2.

## Instructions

**Use the code-quality:markdown-linting skill to handle the complete linting workflow.**

The markdown-linting skill provides:

- **Validation using markdownlint-cli2** (CLI tool or npm scripts)
- **Auto-fix capabilities** for fixable linting issues
- **Configuration guidance** for `.markdownlint-cli2.jsonc`
- **Rule explanations** and troubleshooting
- **VS Code integration** and GitHub Actions setup (optional/advanced)

**Simply invoke the skill and follow its guidance:**

```text
Use the code-quality:markdown-linting skill to run linting validation.

{IF ARGUMENTS PROVIDED}
Target the following files/folders: {ARGUMENTS}

The user provided: "{ARGUMENTS}"
This could be:
- Specific file paths (e.g., "README.md", "docs/setup.md")
- Folder paths (e.g., "docs/", ".claude/skills/")
- Glob patterns (e.g., "docs/**/*.md", "*.md")
- Natural language descriptions (e.g., "only skill documentation", "git-related docs")

Interpret the targeting instructions and construct the appropriate markdownlint-cli2 command.
{ENDIF}

{IF NO ARGUMENTS}
Run validation on all markdown files in the project (default behavior).
{ENDIF}

Follow the skill's workflow:
1. Determine the appropriate linting command (npx or npm scripts)
2. Execute validation on targeted or all markdown files
3. Report results (errors found or clean validation)
4. **Automatically run auto-fix** if fixable issues are detected (DO NOT ask for confirmation)
5. Report what was fixed and any remaining unfixable issues
6. Explain any rule violations found
```

**IMPORTANT**: Do NOT run linting commands directly without consulting the skill. The markdown-linting skill ensures:

- Proper command construction (npx vs npm scripts)
- Configuration compliance (respects `.markdownlint-cli2.jsonc`)
- Rule explanations and context
- Auto-fix guidance for fixable issues
- Proper error interpretation and reporting

Let the skill guide the complete workflow.

## Examples

### Example 1: Lint All Files

```text
User: /code-quality:lint-md

Claude: [Invokes code-quality:markdown-linting skill]
Running linting on all markdown files...

$ npm run lint:md
# or
$ npx markdownlint-cli2 "**/*.md"

All markdown files pass linting validation
```

### Example 2: Lint Specific Folder

```text
User: /code-quality:lint-md docs/

Claude: [Invokes code-quality:markdown-linting skill with targeting]
Running linting on docs/ folder...

$ npx markdownlint-cli2 "docs/**/*.md"

Found 3 linting errors in docs/setup.md:
- Line 45: MD022/blanks-around-headings
- Line 78: MD009/no-trailing-spaces
- Line 102: MD022/blanks-around-headings

Auto-fixing...
$ npx markdownlint-cli2 "docs/**/*.md" --fix
All issues fixed
```

### Example 3: Lint Specific Files

```text
User: /code-quality:lint-md README.md CLAUDE.md

Claude: [Invokes code-quality:markdown-linting skill with targeting]
Running linting on specified files...

$ npx markdownlint-cli2 README.md CLAUDE.md

README.md: No issues found
CLAUDE.md: 2 issues found (auto-fixable)
- Line 23: MD009/no-trailing-spaces
- Line 67: MD012/no-multiple-blanks

Auto-fixing...
$ npx markdownlint-cli2 README.md CLAUDE.md --fix
All issues fixed
```

### Example 4: Natural Language Targeting

```text
User: /code-quality:lint-md only the skill documentation

Claude: [Invokes code-quality:markdown-linting skill with interpretation]
Interpreting target: "only the skill documentation"
Targeting: .claude/skills/**/*.md

$ npx markdownlint-cli2 ".claude/skills/**/*.md"

Checking 9 skill files...
All skill documentation passes linting validation
```

### Example 5: Glob Pattern

```text
User: /code-quality:lint-md .claude/**/*.md

Claude: [Invokes code-quality:markdown-linting skill with pattern]
Running linting on .claude/**/*.md pattern...

$ npx markdownlint-cli2 ".claude/**/*.md"

Found issues in 2 files:
- .claude/memory/workflows.md: 1 issue (MD022)
- .claude/commands/lint-md.md: 3 issues (MD009, MD012, MD022)

Total: 4 fixable issues

Auto-fixing...
$ npx markdownlint-cli2 ".claude/**/*.md" --fix
All issues fixed
```

## Command Design Notes

This command is designed to work with the code-quality:markdown-linting skill, which provides the actual linting logic, rule explanations, and troubleshooting guidance. This command focuses on:

- **Argument interpretation**: Parsing user-provided targeting instructions
- **Delegation**: Invoking the markdown-linting skill with context
- **Simplicity**: Minimal orchestration, maximum skill leverage

The markdown-linting skill handles:

- **Linting execution**: Running markdownlint-cli2 with correct arguments
- **Result interpretation**: Explaining errors and violations
- **Auto-fix guidance**: Offering and executing fixes
- **Configuration**: Respecting `.markdownlint-cli2.jsonc` settings
- **Troubleshooting**: Helping resolve linting issues

This separation of concerns keeps both the command and skill focused and maintainable.
