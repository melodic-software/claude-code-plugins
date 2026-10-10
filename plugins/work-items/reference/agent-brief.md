# Agent-Brief Template

Template for items carrying the autonomous-eligible role label (default `agent-ready`). The brief is what an AFK agent builds against: where it and the issue body or comment thread disagree, the brief wins, and the rest is background reading.

## Rules for the fields

An agent may pick up a labeled item weeks after it was written, so sort each fact by whether it
goes stale. A path, a line number or today's file layout stops being true once a file is split,
merged into another or given a new home. A type's contract, a config key or a test command stays
true through all three. Four fields carry a rule that keeps them to the second kind, and also
leaves the agent nothing it must ask about before finishing.

| Field | Rule | Write | Avoid |
|---|---|---|---|
| Key interfaces | **Name by contract** | the type, function signature, config key or observable behavior that changes | file paths, line numbers, and anything that holds only while the code keeps today's layout |
| Desired behavior | **Describe the end state** | what is true once the change lands, edge cases and failure handling included; the agent reads the code and picks the edit | edit instructions |
| Acceptance criteria | **Yes-or-no checks** | checks the agent runs or reads that each give a yes or no without the others | a wish with no test |
| Out of scope | **Named limits** | the neighboring code and features this change leaves as they are | an empty section: the agent then decides alone where the change stops, and may add work nobody asked for |

Each pair below comes from one of two changes, a retry backoff cap and a CSV export fix:

| Field | Usable | Not usable |
|---|---|---|
| Acceptance criteria | "`npm test -- retry` passes, including a new case where the backoff hits `maxDelay`." | "Retries behave better." |
| Acceptance criteria | "Exporting a report with zero rows produces a file that holds only the header line." | "Empty exports work." |
| Desired behavior | "`ReportExporter.toCsv()` writes the header row even when the result set is empty." | "Move the header write above the `for` loop in `export.ts`." |
| Desired behavior | "`RetryPolicy` gains a `maxDelay` setting; once the computed backoff exceeds it, the delay is clamped to `maxDelay`." | "In `retry.go`, add an `if` after the multiply on line 88." |

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

The brief can be the issue body itself or a comment; a comment starts with the `## Agent Brief` heading, which is how agents find it. A slice `/work-items:decompose` publishes already carries these fields as body sections (Outcome, Key interfaces, Done when, Out of scope) and needs no separate `## Agent Brief` block.

### Key interfaces from a design

When the item comes from a plan whose PLAN.md has a `## Design` section, **Key interfaces** quotes the part of that section the item touches (contracts, type shapes, module boundaries, variation verdicts, and the conventions followed) rather than paraphrasing it, with each file path replaced by the type or module it names. Conventions followed are carried as the names of the ADRs and rules the design follows, never their file paths. The quote is the design guardrail the executing agent works within; the design directory it came from is never published.

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
