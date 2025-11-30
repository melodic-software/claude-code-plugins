---
name: gemini-cli-execution
description: Expert guide for executing the Google Gemini CLI (`gemini`) in non-interactive, headless, and automation modes. Covers command syntax, piping input, handling output, context management, and error handling. Delegates to gemini-cli-docs for official command references.
allowed-tools: Read, Glob, Grep, Skill, Bash
---

# Gemini CLI Execution

## 🚨 MANDATORY: Invoke gemini-cli-docs First

> **STOP - Before executing ANY Gemini CLI command:**
>
> 1. **INVOKE** `gemini-cli-docs` skill
> 2. **QUERY** for the specific CLI command syntax (e.g., "headless mode", "piping input")
> 3. **BASE** all execution patterns EXCLUSIVELY on official documentation loaded

## Overview

This skill provides the operational knowledge to execute the `gemini` binary effectively within scripts, sub-agents, and automation workflows. It focuses on **non-interactive** usage.

## When to Use This Skill

**Keywords:** run gemini, execute gemini, gemini cli command, headless gemini, pipe to gemini, automated planning, gemini query, interactive shell

**Use this skill when:**

- Invoking Gemini CLI from an agent (e.g., `gemini-planner`)
- Running one-off queries: `gemini query "prompt"`
- Piping context: `cat file.js | gemini query "refactor this"`
- Using **Interactive Shell** for tools like `vim` or `top`
- scripting complex workflows involving Gemini

## Execution Patterns

### 1. Single Shot Query (Non-Interactive)

Use the `query` command (or equivalent based on version) for direct prompts.

```bash
gemini query "Create a plan for a React app"
```

### 2. Piping Context

Pass file content or logs via stdin.

```bash
cat logs.txt | gemini query "Analyze these error logs"
```

### 3. Context via Flags

If the CLI supports adding context via flags (verify with `gemini-cli-docs`).

```bash
gemini query --context file.js "Explain this code"
```

### 4. Interactive Shell Mode

Enable interactive shell for commands requiring user input (e.g., `vim`, `git rebase`).

- **Enable:** Set `tools.shell.enableInteractiveShell: true` in `settings.json`.
- **Usage:** `gemini query "run vim file.txt"` (User must handle input).

## Keyword Registry (Delegates to gemini-cli-docs)

| Topic | Query Keywords |
| :--- | :--- |
| **Basic Query** | `gemini query command`, `cli prompt syntax` |
| **Headless/Scripting** | `headless mode`, `non-interactive`, `scripting gemini` |
| **Context Management** | `cli context flags`, `adding files to cli` |
| **Output Formatting** | `json output`, `raw output`, `quiet mode` |
| **Interactive Shell** | `interactive shell tool`, `enableInteractiveShell`, `interactive commands` |

## Quick Decision Tree

**What do you want to do?**

1. **Ask a Question** -> `gemini query "Question"`
2. **Analyze a File** -> `cat file | gemini query "Analyze"`
3. **Generate a Plan** -> `gemini query "Plan for X"`
4. **Run Interactive Tool** -> `gemini query "run interactive command"`

## Troubleshooting

**Issue:** CLI hangs or waits for input.
**Fix:** Ensure you are NOT using the interactive chat mode (`gemini chat`). Use specific query/prompt commands.

## References

**Official Documentation:**
Query `gemini-cli-docs` for:

- "cli commands"
- "headless usage"
