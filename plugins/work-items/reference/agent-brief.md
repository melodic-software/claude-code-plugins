# Agent-Brief Template

Template for items carrying the autonomous-eligible role label (default `agent-ready`). The brief is what an AFK agent builds against: where it and the issue body or comment thread disagree, the brief wins, and the rest is background reading.

## Principles

### Durability over precision

A labeled item can wait a long time before an agent picks it up, and the code keeps moving while it waits. Write a brief that a rename, a file move, or a refactor does not invalidate.

- Name what the agent should change by its contract: the type, the function signature, the config key, the observable behavior.
- Leave out file paths and line numbers; both drift.
- Do not lean on how the code happens to be arranged today.

### Outcomes, not steps

State the result the change must produce and let the agent work out the edit. It reads the code itself and chooses its own approach.

- **Good:** "`RetryPolicy` gains a `maxDelay` setting; once the computed backoff exceeds it, the delay is clamped to `maxDelay`."
- **Bad:** "In `retry.go`, add an `if` after the multiply on line 88."
- **Good:** "`/work-items:triage` run against an empty queue prints a single line saying nothing needs triage."
- **Bad:** "Insert an early return at the top of the loop."

### Checkable acceptance criteria

Each criterion is something the agent can run or read and get a yes or no from, on its own.

- **Good:** "`npm test -- retry` passes, including a new case where the backoff hits `maxDelay`."
- **Bad:** "Retries behave better."

### A stated boundary

List what the change must leave alone, so the agent neither adds unrequested extras nor guesses about neighboring features.

## Template

```markdown
## Agent Brief

**Type:** Bug / Feature / Task (the issue's type: native Issue Type on org repos, `type:` label on personal / non-org repos)
**Summary:** <the change, in one line>

**Current behavior:**
<What the code does today. A bug: the faulty result. A feature: the existing behavior it extends.>

**Desired behavior:**
<What the code does once this lands, including how it handles edge cases and failures.>

**Key interfaces:**
- `TypeName`: <the change and the reason for it>
- `FunctionName()` return type: <today's value vs the intended one>
- Config shape: <settings added or changed>

**Acceptance criteria:**
- [ ] <a check with a yes-or-no result>
- [ ] <a check with a yes-or-no result>

**Out of scope:**
- <something this change must not touch>
- <a nearby feature that stays as it is>
```

## When to use

Apply this template when:

- Issue receives the autonomous-eligible role label (default `agent-ready`)
- Issue is intended for AFK agent execution (`/schedule`, `/loop`, Codex)
- Issue body is vague and needs structuring for autonomous execution

The brief can be the issue body itself or a comment; a comment starts with the `## Agent Brief` heading, which is how agents find it.

### PR-variant briefs

When the item is a pull request (or otherwise carries attached code), keep the same heading and sections. Do **not** replace the bug/feature template above. Specialize two fields:

- **Current behavior** = **current-behavior-of-the-diff**: what the attached change actually does today (as written), including gaps vs the verified requirement.
- **Desired behavior** = **finish-what-exists**: remaining work that makes the attached change mergeable, whether by adopting, reworking, or completing it, rather than restarting from a blank implementation.

In this variant the brief describes the work still owed on the attached change, not a new implementation. Use it only for a PR or attached code; ordinary bug and feature items keep Current/Desired as the template defines them.

## Anti-patterns

| Bad | Why | Fix |
|-----|-----|-----|
| File paths in key interfaces | Go stale within days | Name types and functions instead |
| "Fix the bug" acceptance criteria | Not verifiable | "Running X produces Y" |
| No out-of-scope section | Agent gold-plates | List 2-3 explicit boundaries |
| Procedural steps ("open file, add line") | Agent makes different implementation choices | Describe desired behavior |
| Implementation-specific ("use a HashMap") | Constrains agent unnecessarily | Describe the requirement the data structure must satisfy |
| Restarting a PR from a blank implementation | Ignores attached code | Finish what exists; current-behavior-of-the-diff |
