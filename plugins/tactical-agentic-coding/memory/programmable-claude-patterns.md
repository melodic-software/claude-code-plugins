# Programmable Claude Code Patterns

Patterns for running Claude Code programmatically from shell, Python, and TypeScript. From TAC Lesson 001.

## Why Programmable Matters

Claude Code is a **programmable** agentic coding tool. You can run it from any programming language that has terminal access.

**This is critical because:**

- We want to build systems that build systems
- We need to embed agents and workflows across the software development lifecycle
- Agentic prompts shouldn't be limited to the Claude Code UI - they should run everywhere

**Key capability:** Claude Code runs in the terminal, so it can be embedded across all developer environments, including fully agentic environments where you're not even present.

## The Core Command

All patterns use the same core command:

```bash
claude -p "<prompt_content>"
```markdown

The `-p` flag runs Claude Code in non-interactive mode with the provided prompt.

## Shell Pattern

```bash
#!/bin/bash
PROMPT_CONTENT="$(cat prompt.md)"
OUTPUT="$(claude -p "$PROMPT_CONTENT")"
echo "$OUTPUT"
```markdown

**Usage:** `bash script.sh`

## Python Pattern

```python
import subprocess
import sys

def main():
    with open("prompt.md", "r") as f:
        prompt_content = f.read()

    command = ["claude", "-p", prompt_content]

    try:
        result = subprocess.run(command, capture_output=True, text=True)
        print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        sys.exit(result.returncode)
    except Exception as e:
        print(f"Error executing command: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
```markdown

**Usage:** `uv run script.py` or `python script.py`

## TypeScript Pattern (Bun)

```typescript
import { $ } from "bun";
import { readFileSync } from "fs";

async function main() {
    try {
        const promptContent = readFileSync("prompt.md", "utf-8");
        const output = await $`claude -p ${promptContent}`.text();
        console.log(output);
    } catch (error) {
        console.error(`Error executing command: ${error}`);
        process.exit(1);
    }
}

if (import.meta.main) {
    main();
}
```markdown

**Usage:** `bun run script.ts`

## Agentic Prompt Syntax

Prompts can use a structured syntax for multi-step workflows:

```markdown
RUN:
    checkout a new/existing "feature-branch" git branch

CREATE src/feature.py:
    implement the feature with proper error handling

RUN:
    uv run pytest tests/
    git add .
    git commit -m "Add new feature"

REPORT:
    respond with test results and commit hash
```markdown

### Block Types

| Block | Purpose |
| ------- | --------- |
| `RUN:` | Execute shell commands |
| `CREATE {filename}:` | Create a file with natural language spec |
| `REPORT:` | Request specific output or summary |

## Permission Configuration

Scope tool access with `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Write",
      "Edit",
      "Bash(uv run:*)",
      "Bash(git checkout:*)",
      "Bash(git branch:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "WebSearch"
    ]
  }
}
```yaml

**Pattern:** Use wildcard patterns (`Bash(command:*)`) to allow specific commands while restricting others.

## When to Use Programmatic Invocation

Use programmatic Claude Code when:

- **CI/CD pipelines** - Automated code review, test generation, documentation
- **Git hooks** - Pre-commit validation, post-merge actions
- **Scheduled tasks** - Periodic codebase maintenance, dependency updates
- **Event triggers** - Issue triage, PR analysis, deployment scripts
- **Custom tooling** - Domain-specific agents embedded in your workflow

## Key Insight

The fact that Claude Code runs in the terminal means:

- It can run across all developer environments
- It can run in fully agentic environments without human presence
- It can be embedded inside codebases, firing off when needed
- It does the right thing at the right time

This is the foundation for building systems that build systems.

## Related

- @tac-philosophy.md - Core TAC philosophy and mindset
- @core-four-framework.md - The Core Four framework

---

**Source:** Lesson 001 - Hello Agentic Coding, tac-1 repository
**Last Updated:** 2025-12-04
