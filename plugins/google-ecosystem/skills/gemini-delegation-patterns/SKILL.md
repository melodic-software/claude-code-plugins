---
name: gemini-delegation-patterns
description: Strategic patterns for Claude-to-Gemini delegation. Covers decision criteria, execution patterns, result parsing, and error handling. Use when determining if a task should be delegated to Gemini CLI.
allowed-tools: Read, Glob, Grep, Skill
---

# Gemini Delegation Patterns

## Overview

Meta-skill for determining when and how Claude should delegate to Gemini CLI. Documents decision criteria, execution patterns, and result handling.

## When to Use This Skill

**Keywords:** delegate to gemini, use gemini, gemini vs claude, which agent, hand off, gemini better, claude or gemini, second brain

**Use this skill when:**

- Deciding whether a task should go to Gemini
- Planning cross-agent workflows
- Understanding Gemini CLI integration points
- Optimizing task distribution between Claude and Gemini

## Decision Matrix

| Scenario | Delegate to Gemini? | Rationale |
|----------|---------------------|-----------|
| Interactive TUI needed (vim, git rebase -i) | YES | Claude cannot handle PTY |
| Risky shell command | YES | Gemini sandbox isolation |
| Large codebase analysis (100K+ tokens) | YES | Gemini 1M+ context window |
| GCP/Firebase/Vertex auth required | YES | Native Google integration |
| Need instant rollback capability | YES | Gemini checkpointing |
| Quick code edit | NO | Claude is faster |
| Multi-turn conversation | NO | Claude maintains context better |
| Complex reasoning with files | NO | Claude's Edit tool is superior |
| Need persistent session | NO | Claude Code has better UX |
| Security-sensitive analysis | MAYBE | Gemini sandbox + Claude reasoning |

## Execution Patterns

### Pattern 1: Fire-and-Forget (Headless)

Best for: Quick queries, analysis, code generation

```bash
gemini -p "{prompt}" --output-format json
```

**When to use:**

- One-off questions
- Code analysis without modification
- Documentation generation

### Pattern 2: Sandboxed Execution

Best for: Risky commands, untrusted code

```bash
gemini -s -p "Execute: {command}" --output-format json --yolo
```

**When to use:**

- Running npm install for unknown packages
- Executing user-provided scripts
- Testing destructive operations
- Analyzing potentially malicious code

### Pattern 3: Checkpointed Experimentation

Best for: Risky refactors, migrations

1. Ensure checkpointing enabled in settings.json
2. Execute refactor via Gemini
3. Verify results (run tests)
4. `/restore` if failed, keep if passed

**When to use:**

- Large-scale refactoring
- Framework migrations
- Database schema changes
- Breaking API modifications

### Pattern 4: Interactive Handoff

Best for: TUI commands (vim, rebase, htop)

1. Inform user of handoff requirement
2. Start Gemini with interactive flag
3. User interacts directly with PTY
4. Claude resumes after completion

**When to use:**

- `git rebase -i`
- `vim` / `nano` / `emacs`
- `htop` / `top`
- Database CLIs (psql, mysql, redis-cli)

### Pattern 5: Bulk Analysis

Best for: Large codebases exceeding Claude's context

```bash
cat $(find src -name "*.ts") | gemini -p "Analyze architecture" --output-format json -m gemini-2.5-flash
```

**When to use:**

- Full codebase architecture analysis
- Cross-file dependency mapping
- Large log file analysis (100K+ lines)
- Documentation generation for entire modules

### Pattern 6: Second Opinion

Best for: Validation and alternative perspectives

```bash
gemini -p "REVIEW MODE (read-only): Analyze this independently: {content}" --output-format json
```

**When to use:**

- Validating security analysis
- Reviewing architectural decisions
- Checking refactoring plans
- Getting alternative implementation approaches

## Model Selection Guide

| Model | Context | Cost | Best For |
|-------|---------|------|----------|
| gemini-2.5-flash | 1M+ tokens | Lower | Bulk analysis, simple tasks |
| gemini-2.5-pro | 2M+ tokens | Higher | Complex reasoning, quality critical |

**Use Flash when:**

- Processing large files
- Doing bulk analysis
- Cost is a concern
- Task is straightforward

**Use Pro when:**

- Complex reasoning needed
- Quality is critical
- Task requires deep understanding
- Context exceeds 1M tokens

## Quick Decision Tree

```text
START
  |
  v
Does it need a TUI? ─────────────> YES ─> gemini-interactive-shell agent
  |
  NO
  |
  v
Is it risky/destructive? ────────> YES ─> gemini-sandboxed-executor agent
  |
  NO
  |
  v
Is it a large file/codebase? ────> YES ─> gemini-bulk-analyzer agent
  |
  NO
  |
  v
Need safety net for experiments? ─> YES ─> gemini-checkpoint-experimenter agent
  |
  NO
  |
  v
Want validation/second opinion? ──> YES ─> gemini-second-opinion agent
  |
  NO
  |
  v
Simple query? ───────────────────> YES ─> /gemini-query command
  |
  NO
  |
  v
Keep in Claude ─────────────────────────> Use Claude's native tools
```

## Keyword Registry (Delegates to gemini-cli-docs)

| Topic | Query Keywords |
|-------|----------------|
| Headless mode | `headless json output`, `output format`, `-p flag` |
| Sandboxing | `sandbox docker podman`, `seatbelt`, `-s flag` |
| Checkpointing | `checkpoint restore`, `rollback`, `/restore command` |
| Interactive | `interactive shell`, `enableInteractiveShell`, `PTY` |
| Model selection | `model routing`, `flash vs pro`, `-m flag` |
| Auto-approve | `yolo mode`, `--yolo`, `auto approve` |

## Error Handling

### Common Errors and Recovery

| Error | Cause | Recovery |
|-------|-------|----------|
| JSON parse error | Malformed output | Retry with `--output-format json` |
| Timeout | Long-running task | Increase timeout, use streaming |
| Auth error | Missing credentials | Check `gemini auth` status |
| Sandbox error | Missing container | Build sandbox image first |

### Retry Strategy

```bash
# Retry with exponential backoff
for i in 1 2 4; do
  result=$(gemini -p "query" --output-format json 2>&1) && break
  sleep $i
done
```

## References

Query `gemini-cli-docs` for official documentation on:

- "headless mode usage"
- "sandbox configuration"
- "checkpointing setup"
- "model selection"
