# Agent Perspective Checklist

Pre-task checklist to adopt your agent's perspective. From TAC Lesson 002.

## Before Starting Any Agentic Task

Your agent starts each session blank - no context, no memories. Run through this checklist to ensure success.

---

## Context Checklist

**Does my agent have what it needs to understand the task?**

- [ ] CLAUDE.md exists with relevant project context
- [ ] README.md explains project structure
- [ ] Task requirements are clearly specified
- [ ] Examples of expected output provided (if applicable)
- [ ] Relevant files are accessible (not in .gitignore if needed)

**Quick fix**: If agent lacks context, add it to CLAUDE.md or provide in prompt.

---

## Visibility Checklist

**Can my agent see what's happening?**

- [ ] Application has stdout logging for success AND errors
- [ ] Error messages are descriptive (not silent failures)
- [ ] State changes are logged (file created, API called, etc.)
- [ ] Debug information available when needed

**Quick fix**: Add `print()` statements at key points. Agent needs to see errors to fix them.

---

## Validation Checklist

**Can my agent verify its work?**

- [ ] Tests exist for the code being modified
- [ ] Tests can be run via simple command (`npm test`, `pytest`, etc.)
- [ ] Tests provide clear pass/fail feedback
- [ ] Tests run quickly (agent can iterate if needed)

**Quick fix**: Tests are the highest leverage point. Add them first.

---

## Navigation Checklist

**Can my agent find things efficiently?**

- [ ] Files are organized consistently
- [ ] Entry points are obvious (main.py, index.ts, server.py)
- [ ] Related files are grouped together
- [ ] File names are descriptive
- [ ] Files are reasonably sized (< 1000 lines)

**Quick fix**: Refactor large files, improve naming, document entry points.

---

## Tools Checklist

**Does my agent have the capabilities it needs?**

- [ ] Required tools are allowed in permissions
- [ ] MCP servers configured (if needed)
- [ ] External APIs accessible (if needed)
- [ ] File system permissions appropriate

**Quick fix**: Update `.claude/settings.json` to allow required tools.

---

## Communication Checklist

**Have I communicated the work clearly?**

- [ ] Task broken into clear steps (if complex)
- [ ] Success criteria defined
- [ ] Constraints specified (what NOT to do)
- [ ] Priority order clear (if multiple items)

**Quick fix**: Write a plan before handing off complex work.

---

## Quick Reference Card

### Before every task, ask

1. **Context**: What does agent see?
2. **Visibility**: Can agent see errors?
3. **Validation**: Can agent verify work?
4. **Navigation**: Can agent find things?
5. **Tools**: Can agent act?
6. **Communication**: Does agent understand the task?

### When task fails, ask

1. Which checklist item was missing?
2. How can I prevent this next time?
3. What leverage point needs improvement?

---

## Red Flags

**Stop and fix before proceeding:**

- Agent asks clarifying questions repeatedly -> Context missing
- Agent makes same mistake multiple times -> Validation missing
- Agent can't find files it needs -> Navigation issue
- Agent reports "something went wrong" -> Visibility missing
- Agent attempts forbidden actions -> Tools misconfigured

---

## The Agent's Questions

Imagine you ARE the agent. Ask yourself:

1. "Do I know what I'm supposed to do?" -> Communication
2. "Can I see the code and context I need?" -> Context
3. "Can I see if my changes work?" -> Validation
4. "Can I see when things go wrong?" -> Visibility
5. "Can I find the files I need?" -> Navigation
6. "Can I perform the actions required?" -> Tools

If ANY answer is "no", fix it before starting.

---

## Related

- @12-leverage-points.md - What to improve when checks fail
- @agentic-kpis.md - Measure improvement over time
- @tac-philosophy.md - Why this matters

---

**Source:** Lesson 002 - 12 Leverage Points of Agentic Coding
**Last Updated:** 2025-12-04
