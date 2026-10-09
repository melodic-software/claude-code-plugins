---
description: "Audit a repository's developer tooling: scripts, command-line tools, skills, hooks, subagents and MCP configs. Read-only findings report on a bare run; changes only after an explicit yes. Use when: 'audit our tooling', 'what scripts and tools does this repo have', 'find duplicate or stale scripts', 'review our CLIs'."
argument-hint: "[path or repo ...]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Inventory a repository's developer tooling and report findings, read-only by default
---

# Audit developer tooling

Audit the tooling in `$ARGUMENTS`, or in the current repository when none is given. Other
repositories are read only when named.

## Contract

- A bare invocation is read-only: it reads and reports findings, and changes nothing.
- A change happens only after the user says yes to that specific change.

## Steps

1. Inventory the repository's scripts (task-runner entries included), command-line tools, skills,
   hooks, subagents and MCP configs. Done when every tooling directory has been listed.
2. Report findings per item with the file and line that support each one. Done when no finding
   lacks a file reference.
3. Offer each fix as a proposal and wait for the user's yes before applying it. Done when every
   proposal is answered yes or declined.

## Next

/overengineering:justify <artifact> decides whether a tool the audit flagged as unused should be retired.

## Gotchas

- A finding without a file reference is a guess; drop it or mark it unverified.
- Running without a yes never edits, even for a one-line fix.
