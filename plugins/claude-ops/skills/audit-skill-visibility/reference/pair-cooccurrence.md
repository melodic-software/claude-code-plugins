# Pair co-occurrence — does skill B get invoked where skill A ran?

Reference for `scripts/skill-pair-cooccurrence.sh`. A different question from visibility,
answered from the same `skill-usage.jsonl` store: not *can* the model see a skill, but does
one skill's run actually coincide with another's. The case it was written for is "skill X's
instructions tell the model to invoke skill Y — does that happen?"

```bash
scripts/skill-pair-cooccurrence.sh --pair implementation:implement,tdd:principles
scripts/skill-pair-cooccurrence.sh --pair a:b,c:d --json      # machine-readable
```

| Flag | Meaning |
|---|---|
| `--store PATH` | store to read; defaults to `<git toplevel>/.claude/observability/skill-usage.jsonl` |
| `--pair A,B` | ordered pair, caller first |
| `--floor-days N` | minimum observed span before any rate is reportable (default 30) |
| `--floor-groups N` | minimum caller-bearing groups before any rate is reportable (default 5) |
| `--json` | one JSON object instead of prose |

Exit `0` for a reading (verdict **or** withheld), `2` for a missing/unreadable store, `3` for
bad arguments.

## It is a proxy — do not strip the caveat

The `SkillUse` record carries **no caller attribution**. A PostToolUse hook on the Skill tool
receives `tool_name`, `tool_input`, and `tool_response`; nothing in that payload names the skill
whose instructions caused the call. So the script cannot observe "Y was invoked *by* X" — only
that both fired in the same `(project_id, branch)` group, ordered by timestamp. A Y the user
typed by hand counts identically to one X produced.

There is no session id either. `(project_id, branch)` is the nearest available partition, so two
sessions on one branch collapse into one group and one session spanning a branch switch splits
into two.

The caveat prints in **both** renderers, prose and `--json`. A machine consumer stripping it is
the same defect as a human not seeing it.

## It inherits the refusal

Below the 30-day exposure floor — the same constant `audit_skill_visibility.py` uses — or below
the minimum denominator, the script returns `WITHHELD` with a reason instead of a small number.

**The empty denominator is the trap it exists to refuse.** If the caller never ran, "0% of its
sessions also used the callee" is a claim about a population that was never observed, not a rate
of zero. That inversion is the whole reason for a separate branch, and it carries a regression
test verified to fail when the branch is removed.

## What would replace the proxy

Not a wider `SkillUse` record. Caller identity is absent from the hook's *input*, not merely from
its schema, so widening the write would have nothing to write; recovering it would mean reading
the session transcript, which turns a bounded telemetry hook into a conversation reader and
crosses the boundary `observability/context/privacy.md` guards.

The nearer signal needs no change and already ships: OTEL's `claude_code.skill_activated` carries
`invocation_trigger`, separating `user-slash` from `claude-proactive`. That is the axis a "does
the model reach for it unprompted" question actually wants, and the tier model already gates it
as `T-full`-only.
