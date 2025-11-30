# Active Hooks

**Last Updated:** 2025-11-27

## Overview

This document lists all currently active hooks in the repository with their configurations and purposes.

## Hooks List

### 1. Prevent Backup Files

**Purpose:** Block creation of .bak, .backup, and similar files for git-tracked content

**Configuration:**

- **Event:** PreToolUse
- **Matcher:** `Write|Edit` (string format)
- **Location:** `.claude/hooks/prevent-backup-files/`
- **Implementation:** `bash/prevent-backup-files.sh`
- **Config:** See `prevent-backup-files/config.yaml` in hooks directory
- **Tests:** See `prevent-backup-files/tests/` in hooks directory
- **CLAUDE.md Automation:** Removes need for manual rule at line 54

**How it works:**

- Intercepts Write and Edit tool calls
- Checks if file path contains backup extensions (.bak, .backup, .tmp~, etc.)
- Checks if file is git-tracked
- Blocks operation if backup file would be created for tracked content

### 2. Require GPG Signing

**Purpose:** Block git commits with --no-gpg-sign flag

**Configuration:**

- **Event:** PreToolUse
- **Matcher:** `Bash` (string format)
- **Location:** `.claude/hooks/require-gpg-signing/`
- **Implementation:** `bash/require-gpg-signing.sh`
- **Config:** See `require-gpg-signing/config.yaml` in hooks directory
- **Tests:** See `require-gpg-signing/tests/` in hooks directory
- **CLAUDE.md Automation:** Removes need for manual rule at line 52

**How it works:**

- Intercepts Bash tool calls
- Detects git commit commands
- Checks for --no-gpg-sign or --no-verify flags
- Blocks operation if signing would be bypassed

### 3. Require Explicit Commit Approval

**Purpose:** Ask for confirmation before direct git commits (encourages use of git-commit skill)

**Configuration:**

- **Event:** PreToolUse
- **Matcher:** `Bash` (string format)
- **Location:** `.claude/hooks/require-explicit-commit/`
- **Implementation:** `bash/require-explicit-commit.sh`
- **Config:** See `require-explicit-commit/config.yaml` in hooks directory
- **Tests:** See `require-explicit-commit/tests/` in hooks directory
- **CLAUDE.md Automation:** Removes need for manual rule at line 53

**How it works:**

- Intercepts Bash tool calls
- Detects direct git commit commands (not via git-commit skill)
- Prompts user for explicit approval
- Encourages use of git-commit skill for better workflow

### 4. Block Absolute Paths in Documentation

**Purpose:** Block absolute paths in markdown files

**Configuration:**

- **Event:** PreToolUse
- **Matcher:** `Write|Edit` (string format)
- **Location:** `.claude/hooks/block-absolute-paths/`
- **Implementation:** `bash/block-absolute-paths.sh`
- **Config:** See `block-absolute-paths/config.yaml` in hooks directory
- **Tests:** See `block-absolute-paths/tests/` in hooks directory
- **CLAUDE.md Automation:** Removes need for manual rule at line 57

**How it works:**

- Intercepts Write and Edit tool calls for markdown files
- Scans content for absolute path patterns (Windows drive letters, Unix absolute paths)
- Allows platform-specific teaching examples with placeholders
- Blocks other absolute paths to ensure portability

### 5. Markdown Linting with Auto-Fix

**Purpose:** Automatically lint and auto-fix markdown files using markdownlint-cli2

**Configuration:**

- **Event:** PostToolUse
- **Matcher:** `Write|Edit` (string format)
- **Location:** `.claude/hooks/markdown-lint/`
- **Implementation:** `bash/markdown-lint.sh`
- **Config:** See `markdown-lint/config.yaml` in hooks directory
- **Tests:** See `markdown-lint/tests/` in hooks directory
- **Enforcement:** Warn (default), Block, or Log

**How it works:**

- Runs after Write and Edit tool calls for markdown files
- Executes markdownlint-cli2 with auto-fix
- Auto-fixes: Trailing spaces, blank lines, heading spacing, and other fixable errors
- Warns about: Duplicate headings, missing hierarchy, and other unfixable errors
- Respects `.markdownlint-cli2.jsonc` configuration (single source of truth)

### 6. Suggest Parallelization

**Purpose:** Detect parallelizable tasks in user prompts and inject reminder into Claude's context

**Configuration:**

- **Event:** UserPromptSubmit
- **Matcher:** `*` (all prompts)
- **Location:** `.claude/hooks/suggest-parallelization/`
- **Implementation:** `bash/suggest-parallelization.sh`
- **Config:** See `suggest-parallelization/config.yaml` in hooks directory
- **CLAUDE.md Support:** Supports PROACTIVE DELEGATION rule

**How it works:**

- Runs when user submits a prompt, before Claude processes it
- Analyzes prompt text for parallelization patterns (create N things, multi-platform, research, etc.)
- If patterns detected, injects a system reminder into Claude's context
- Never blocks prompts - only provides contextual reminders
- Patterns: create-multiple, multi-platform, analyze-multiple, compare-items, research-task, list-items

## Hooks by Event Type

### PreToolUse Hooks

Hooks that run BEFORE tool execution:

1. **prevent-backup-files** - Blocks backup file creation
2. **require-gpg-signing** - Blocks commits without GPG signing
3. **require-explicit-commit** - Asks approval for direct commits
4. **block-absolute-paths** - Blocks absolute paths in docs

### PostToolUse Hooks

Hooks that run AFTER tool execution:

1. **markdown-lint** - Auto-fixes and validates markdown files

### UserPromptSubmit Hooks

Hooks that run when user submits a prompt (before processing):

1. **suggest-parallelization** - Injects parallelization reminders into context

## Quick Reference by Purpose

**Code Quality:**

- markdown-lint (auto-fix markdown issues)

**Security & Compliance:**

- require-gpg-signing (enforce commit signing)
- require-explicit-commit (encourage skill-based workflow)

**Portability & Best Practices:**

- prevent-backup-files (avoid clutter)
- block-absolute-paths (ensure path portability)

**Workflow Optimization:**

- suggest-parallelization (encourage parallel subagent delegation)

## Adding New Hooks

For the complete workflow on creating new hooks, see [../development/creating-hooks-workflow.md](../development/creating-hooks-workflow.md).
