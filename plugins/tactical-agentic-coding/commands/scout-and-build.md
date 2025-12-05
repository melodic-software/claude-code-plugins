---
description: Execute the scout-then-build pattern for a feature implementation
---

# Scout and Build Command

Execute the foundational orchestration pattern: scout first, then build based on findings.

## Input

$ARGUMENTS - The feature or change to implement

## Workflow

This command implements the two-phase pattern within Claude Code's subagent constraints.

### Phase 1: Scout

1. **Launch scout agent** (Explore subagent, haiku model):
   - Analyze relevant codebase areas
   - Identify existing patterns
   - Map dependencies
   - Document findings

2. **Capture scout report** with:
   - Files analyzed
   - Patterns found
   - Recommendations
   - Implementation approach

### Phase 2: Build

1. **Plan implementation** based on scout report:
   - Files to create
   - Files to modify
   - Tests to add

2. **Execute changes**:
   - Follow existing patterns from scout findings
   - Implement the feature
   - Add tests as appropriate

3. **Report results**:
   - Files created
   - Files modified
   - Implementation summary

## Output Format

```markdown
## Scout and Build Report

**Task:** [feature description]

### Scout Phase

**Duration:** [time]
**Files Analyzed:** [count]

**Key Findings:**
1. [finding]
2. [finding]

**Recommended Approach:**
[implementation strategy]

### Build Phase

**Duration:** [time]

**Files Created:**
- [file]: [purpose]

**Files Modified:**
- [file]: [changes]

**Implementation Summary:**
[what was done]

### Next Steps

[any remaining work or recommendations]
```markdown

## Example

```

/scout-and-build Add user session timeout handling

```markdown

## Implementation Note

This command uses Claude Code's Task tool with Explore subagent for scouting, then performs building in the main context. For true parallel agent orchestration with separate builder agents, use Claude Agent SDK.

## Cross-References

- @agent-lifecycle-crud.md - Scout-Build pattern
- @results-oriented-engineering.md - Report format
- @multi-agent-context-protection.md - Context separation
