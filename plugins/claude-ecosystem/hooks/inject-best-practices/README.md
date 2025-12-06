# inject-best-practices Hook

SessionStart hook that injects a comprehensive best practices reminder at every session start.

## Purpose

Reinforces core behavioral rules using positive framing (what TO do, not what to avoid). Key principles:

- Skill encapsulation (reference by name only)
- Skills-first approach (check for skills before raw tools)
- Progressive disclosure (load on-demand)
- Anti-duplication (link to single source of truth)
- Zero complacency (surface all errors explicitly)
- Implementation integrity (choose quality over shortcuts)
- Positive instructions (use "do X" rather than "don't do Y")

## How It Works

At session start, this hook injects a `<best-practices-reminder>` block into Claude's context. This reminder appears before any user interaction, setting expectations proactively.

**Philosophy:** Reminders are more reliable than detection/enforcement, which can be unreliable due to context variation.

## Configuration

The hook is enabled by default. To disable:

```bash
export CLAUDE_HOOK_INJECT_BEST_PRACTICES_ENABLED=0
```

To re-enable:

```bash
export CLAUDE_HOOK_INJECT_BEST_PRACTICES_ENABLED=1
# or unset the variable
```

## Content Categories

The reminder covers seven sections with positive framing:

1. **Skills & Execution**: Skills-first, execute instructions, encapsulation, delegation
2. **Tool Constraints**: Read before edit, path resolution, natural language
3. **Context & Efficiency**: Progressive disclosure, exploration before solutions
4. **Behavioral**: Positive framing, zero complacency, start simple, ship working solutions
5. **Workflow**: Course correction, extended thinking, temporary workspace
6. **Memory & Documentation**: Anti-duplication, Claude Code topics, official docs
7. **Success Indicators**: Positive examples of correct behavior (replaces "red flags")

Plus a quick verification checklist.

## Token Usage

The reminder content is approximately 950 tokens - comprehensive coverage of Claude Code best practices while remaining efficient for context injection.

## Testing

Run the test script:

```bash
bash plugins/claude-ecosystem/hooks/inject-best-practices/tests/test-inject-best-practices.sh
```

## Related

- `inject-current-date` hook - Similar SessionStart pattern for date injection
- `response-quality/source-citation` hook - Template pattern this hook is based on
