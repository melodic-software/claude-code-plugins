---
description: "When the bundled claude-api skill resolves in this session, prefer its prompt-audit for application-code prompts and model migration; this skill for Claude Code instruction surfaces. Report-only audit of CLAUDE.md, AGENTS.md, rules, skills, agents and hook text for stale, misstated, or conflicting instructions. Use when: 'audit instructions', 'too prescriptive', 'stale Claude Code behavior', 'my @path import is not loading', 'which instruction wins'. Missing text: audit-prompting-postures."
argument-hint: "[scope] [--target-model <version>] [--opinion] [--persist-findings] [--unattended]"
disallowed-tools: Edit, NotebookEdit
user-invocable: true
disable-model-invocation: false
---

# Audit instructions (eval stand-in)

Report-only: it lists findings and edits no file. This stand-in runs no audit; say what it would
check and stop.
