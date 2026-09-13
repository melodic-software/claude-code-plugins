# Hook timing: resolving a budget and judging a candidate against it

Read when a candidate is a hook and the `Too slow` gate needs a threshold, or when a verdict is
about to state a timing number.

## Contents

- [Resolve the budget before citing a number](#resolve-the-budget-before-citing-a-number)
- [What the timing actually costs, per event](#what-the-timing-actually-costs-per-event)
- [Levers to propose instead of a bare threshold](#levers-to-propose-instead-of-a-bare-threshold)
- [Upstream-fact records](#upstream-fact-records)

## Resolve the budget before citing a number

There is no upstream hook latency budget. The hooks documentation has no performance section, so
any fixed number is a house rule and must be labelled as one wherever a verdict cites it.

The measurement from Phase 2.1 is the left side of the comparison, never a source of the budget
itself. The budget is the right side, and it resolves in two rungs:

1. **The consuming repository's own documented budget.** Search its convention docs and rules for a
   stated per-tool-call or per-turn hook ceiling. Where one exists it is authoritative, including
   when it is far stricter than any default you would otherwise pick, and including when it says it
   never relaxes to absorb an overage.
2. **The house-rule fallback.** Where the repository documents no ceiling, treat roughly one second
   per tool call as the working one, and say in the verdict that this is this skill's number rather
   than upstream guidance.

Name which rung applied in every verdict that cites a threshold. A measurement with no budget on the
other side yields no verdict, so rung 2 always supplies one rather than leaving the gate unable to
decide.

A consuming repository that documents a budget and has no headroom left turns a duplicate-hook
candidate into a REJECT, whatever its latency in isolation.

## What the timing actually costs, per event

The cost of a slow hook is not the same on every event, and the difference decides what the gate is
even measuring.

| Event | Can it block? | What slowness costs |
|---|---|---|
| `PreToolUse` | Yes, it blocks the tool call | The user waits before the tool runs |
| `PostToolUse` | No, the tool already ran | Turn latency only; nothing is prevented |
| `PermissionRequest` | Not via exit code 2 | Denial goes through the `decision` object; an `exit 2` gate here is inert |
| Any command hook with `async: true` | No, structurally | Nothing; it runs in the background |

Two consequences for a verdict. A `PostToolUse` candidate can never be rejected for blocking,
because it cannot block, so judge it on turn latency against the resolved budget. And an "async
gate" is a contradiction: `async: true` is valid only on `type: "command"` hooks, and an async hook
cannot return a decision at all.

## Levers to propose instead of a bare threshold

When a hook is too slow for the resolved budget, these are the documented adjustments, in rough
order of how much they save:

- **Narrow the `matcher`** so the hook does not fire on tool calls it cannot act on.
- **Add an `if` rule** so a non-matching call returns before the process spawn.
- **Set `async: true`** where the hook does not need to block, accepting that it can no longer
  return a decision and that its output arrives on the next turn.
- **Set an explicit `timeout`**, since the default for a `command` hook is 600 seconds on most
  events, which is far longer than any interactive budget.

## Upstream-fact records

Both facts below are restated from an upstream page, so each carries its basis, as-of date, and
recheck trigger per the upstream-drift convention. Re-fetch the basis before acting on either; a
date is not authority.

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| `timeout` defaults to 600 seconds for `command`, `http` and `mcp_tool` hooks, lowered to 30 on `UserPromptSubmit` and the model-switch events and 10 on `MessageDisplay`, with `SessionEnd` hooks sharing a 1.5-second budget | [Claude Code hooks reference](https://code.claude.com/docs/en/hooks), common fields | 2026-09-12 | A re-fetch finds the defaults no longer matching this row |
| `PostToolUse` cannot block: exit code 2 shows stderr to Claude and the tool has already run | [Claude Code hooks reference](https://code.claude.com/docs/en/hooks), exit-code-2 behavior per event | 2026-09-12 | A re-fetch finds the per-event table no longer matching this row |
| No official page states a hook latency budget or compares a check in CI against the same check in a hook | Absence checked by reading each page end to end for a performance, latency or placement section: [hooks](https://code.claude.com/docs/en/hooks), [hooks guide](https://code.claude.com/docs/en/hooks-guide), [best practices](https://code.claude.com/docs/en/best-practices), [features overview](https://code.claude.com/docs/en/features-overview). The nearest statements are event-scoped ("SessionStart runs on every session, so keep these hooks fast") and the `SessionEnd` 1.5-second budget, neither of which is a fleet-wide ceiling | 2026-09-12 | A re-fetch of any of the four finds a performance or placement section added |
