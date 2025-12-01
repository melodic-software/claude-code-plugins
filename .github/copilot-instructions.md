# GitHub Copilot Instructions

**Single Source of Truth:** This repository uses `CLAUDE.md` as the canonical source for all AI tooling guidance.

## Instructions for GitHub Copilot

Read and follow all guidance in:

1. **[CLAUDE.md](../CLAUDE.md)** - Comprehensive repository guidance (Quick Reference + detailed documentation)
2. **`.claude/memory/` files** - Referenced via `@.claude/memory/{topic}.md` syntax in CLAUDE.md

CLAUDE.md contains:

- Repository architecture principles
- Documentation standards and workflows
- Quality requirements and validation
- Operational rules (paths, scripts, agents)
- Platform-specific guidance (Windows/macOS/Linux/WSL)
- Anti-duplication rules
- And all other guidance for working with this codebase

## Why CLAUDE.md?

- **Single source of truth**: One canonical location prevents duplication and drift
- **Always current**: Updates happen in one place, benefiting all AI tooling
- **Comprehensive**: Covers all aspects of working with this repository
- **Hierarchical memory**: Imports context-specific guidance on-demand
- **Cross-platform compatible**: Cursor, Claude Code, and GitHub Copilot all use CLAUDE.md

## Repository Context

This is a Claude Code plugins monorepo providing skills, commands, agents, and hooks for the Claude Code ecosystem. Contains 4 plugins: claude-ecosystem, code-quality, google-ecosystem, and git. See README.md and CLAUDE.md for complete documentation.
