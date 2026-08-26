# Full lifecycle (`/source-control:pull-request full`)

What `/source-control:pull-request full` does that running prep, create, monitor, and merge by
hand does not: the phase-to-phase handoff state and the abort points. Read it only when the
invocation carried `full`; every other action routes through the phase table in
[`../SKILL.md`](../SKILL.md).

Run Phase 1 → Phase 2 → Phase 3 → Phase 4 as a continuous flow. Phase transitions are automatic. Don't pause between phases except at **decision gates** where the outcome could vary, plus one interactive-only checkpoint at the create→monitor boundary.

**Create→monitor checkpoint (`full` only):**

After Phase 2 reports the PR URL, detect session mode:

- **Interactive** (no autonomous-session marker like `CLAUDE_CODE_REMOTE=true`): ask the user whether to proceed to Phase 3 (monitor) in this session. Acceptable responses: proceed (continue to Phase 3) / stop (end after create) / handoff (end; another session/routine will pick up monitoring). Default on no-response is stop.
- **Autonomous** (`CLAUDE_CODE_REMOTE=true` or equivalent): no prompt; continue to Phase 3 without pausing. There is no user to ask.

Standalone `create` (not invoked inside `full`) always stops after Phase 2. See [reference/create.md](create.md) §2.6.

**Decision gates (pause for user):**

| Gate | Why it needs input |
|------|-------------------|
| Prep findings have VALID fixes | User decides which to fix vs defer |
| Commit message content | User may want different wording |
| Create→monitor (interactive only, `full` mode) | User may want to hand off monitoring to another session/routine |
| CI failure fix proposal | Fix approach has multiple options |
| Merge confirmation | Irreversible action |

**NOT gates (proceed automatically):**

| Transition | Just do it |
|-----------|-----------|
| Prep complete → create | Obvious next step |
| All [readiness gates](readiness.md) pass → suggest merge | Report with full readiness verdict |
| Comment classified INCORRECT → react + reply | Evidence already gathered |
| Fix pushed → re-monitor | New push = new cycle |

**NEVER auto-proceed on these (even in `full` mode):**

| Condition | Why it's NOT a gate pass |
|-----------|------------------------|
| CI green + no comments yet | Reviewers may not have posted. Cooldown required |
| CI green + failing security scan | Security findings MUST be evaluated before merge |
| CI green + unclassified failures | Every FAILURE needs explicit classification |

In a non-interactive context (cloud session, CI action), minimize gates to merge-only.

---
