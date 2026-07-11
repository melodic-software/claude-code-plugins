# Agent-Brief Template

Template for issues labeled `agent-ready`. An agent brief is the authoritative specification an AFK agent works from. The original issue body and discussion are context — the agent brief is the contract.

## Principles

### Durability over precision

Issues may sit in `agent-ready` for days or weeks. The codebase changes in the meantime. Write the brief so it stays useful even as files are renamed, moved, or refactored.

- **Do** describe interfaces, types, and behavioral contracts
- **Do** name specific types, function signatures, or config shapes
- **Don't** reference file paths — they go stale
- **Don't** reference line numbers
- **Don't** assume current implementation structure remains the same

### Behavioral, not procedural

Describe **what** the system should do, not **how** to implement it. The agent explores the codebase fresh and makes its own implementation decisions.

- **Good:** "The `SkillConfig` type should accept an optional `schedule` field of type `CronExpression`"
- **Bad:** "Open src/types/skill.ts and add a schedule field on line 42"
- **Good:** "When a user runs `/triage` with no arguments, they should see a summary of issues needing attention"
- **Bad:** "Add a switch statement in the main handler function"

### Complete acceptance criteria

The agent needs to know when it's done. Every criterion should be independently verifiable.

- **Good:** "Running the test suite passes with the new validator active"
- **Bad:** "Feature should work correctly"

### Explicit scope boundaries

State what is out of scope. Prevents gold-plating or assumptions about adjacent features.

## Template

```markdown
## Agent Brief

**Type:** bug / feat / chore / refactor (per `type:` label taxonomy)
**Summary:** one-line description of what needs to happen

**Current behavior:**
What happens now. For bugs: the broken behavior.
For enhancements: the status quo the feature builds on.

**Desired behavior:**
What should happen after the work is complete.
Be specific about edge cases and error conditions.

**Key interfaces:**
- `TypeName` — what needs to change and why
- `FunctionName()` return type — current vs desired
- Config shape — new configuration options needed

**Acceptance criteria:**
- [ ] Specific, testable criterion 1
- [ ] Specific, testable criterion 2
- [ ] Specific, testable criterion 3

**Out of scope:**
- Thing that should NOT be changed
- Adjacent feature that might seem related but is separate
```

## When to use

Apply this template when:

- Issue receives the `agent-ready` meta label
- Issue is intended for AFK agent execution (scheduled agents, autonomous loops)
- Issue body is vague and needs structuring for autonomous execution

The brief can be the issue body itself or posted as a comment (prefixed with `## Agent Brief` heading so agents can locate it).

## Anti-patterns

| Bad | Why | Fix |
|-----|-----|-----|
| File paths in key interfaces | Go stale within days | Name types and functions instead |
| "Fix the bug" acceptance criteria | Not verifiable | "Running X produces Y" |
| No out-of-scope section | Agent gold-plates | List 2-3 explicit boundaries |
| Procedural steps ("open file, add line") | Agent makes different implementation choices | Describe desired behavior |
| Implementation-specific ("use a HashMap") | Constrains agent unnecessarily | Describe the requirement the data structure must satisfy |
