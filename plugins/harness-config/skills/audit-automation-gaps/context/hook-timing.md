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
any fixed number is a house rule and must be labeled as one wherever a verdict cites it.

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
| `PostToolUse` | No, the tool already ran | Turn latency on every matching edit, plus whatever it sends the model; nothing is prevented |
| `PostToolBatch` | See the exit-code record below | Turn latency once per batch of parallel tool calls: the in-session formatter slot |
| `PermissionRequest` | Not via exit code 2 | Denial goes through the `decision` object; an `exit 2` gate here is inert |
| Any command hook with `async: true` | No, structurally | Nothing; it runs in the background |

Three consequences for a verdict. A `PostToolUse` candidate can never be rejected for blocking,
because it cannot block, so judge it on turn latency against the resolved budget. A report-only
check (one that only prints findings) is judged on placement before latency: it never belongs on a
per-edit `PostToolUse` hook, however fast, because its output reaches the model on in-between
states and it covers only Claude Code's own edits. Place it in a git `pre-commit` hook on changed
lines, `pre-push` when its measured run is over the commit budget but within 60 s, or CI beyond
that, and flag an existing per-edit one with that placement (house rule:
[check-placement](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/check-placement/README.md#the-rubric)).
A formatter takes the `PostToolBatch` slot only while its median per fire stays at or under 1 s,
and also runs at `pre-commit`. And an "async gate" is a contradiction: `async: true` is valid only
on `type: "command"` hooks, and an async hook cannot return a decision at all.

A git hook's cost is the author's wait at commit or push, paid once per commit rather than per
edit. Judge it against the consuming repository's own commit or push budget where it documents
one, else the house rule above.

## Levers to propose instead of a bare threshold

When a hook is too slow for the resolved budget, these are the documented adjustments, in rough
order of how much they save:

- **Narrow the `matcher`** so the hook does not fire on tool calls it cannot act on.
- **Add an `if` rule** so a non-matching call returns before the process spawn.
- **Set `async: true`** where the hook does not need to block, accepting that it can no longer
  return a decision and that its output arrives on the next turn.
- **Set an explicit `timeout`**, since the default is far longer than any interactive budget on most
  events.

## Upstream-fact records

Each record below states our decision and points at the section that holds the specific, per the
upstream-drift convention. Re-fetch the pointer before acting on either; a date is not authority.

| Decision | Pointer | As of | Recheck trigger |
|---|---|---|---|
| A hook with no explicit `timeout` is judged against the per-type and per-event defaults read live, never a number kept here | When judging a hook's timeout, fetch [hooks: common fields](https://code.claude.com/docs/en/hooks#common-fields) live | 2026-10-11 | That section changes a default, or adds a per-event or per-type exception |
| A `PostToolUse` hook is never treated as a gate, and no report-only check is placed on it per edit | When judging whether a hook can block, fetch the event's row of [hooks: exit code 2 behavior per event](https://code.claude.com/docs/en/hooks#exit-code-2-behavior-per-event) live | 2026-10-11 | That event's row changes its `Can block?` cell |
| No official page states a hook latency budget or compares a check in CI against the same check in a hook | Absence checked by reading each page end to end for a performance, latency or placement section: [hooks](https://code.claude.com/docs/en/hooks), [hooks guide](https://code.claude.com/docs/en/hooks-guide), [best practices](https://code.claude.com/docs/en/best-practices), [features overview](https://code.claude.com/docs/en/features-overview). The nearest statements are event-scoped ("SessionStart runs on every session, so keep these hooks fast") and the `SessionEnd` 1.5-second budget, neither of which is a fleet-wide ceiling | 2026-09-12 | A re-fetch of any of the four finds a performance or placement section added |
