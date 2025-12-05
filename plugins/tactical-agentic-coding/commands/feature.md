---
description: Generate a comprehensive feature implementation plan with user story, implementation phases, and testing strategy from a feature description.
---

# Feature Planning

Create a new plan in `specs/*.md` to implement the Feature using the exact specified markdown Plan Format. Follow the Instructions to create the plan, use the Relevant Files to understand existing patterns.

## Instructions

- You are writing a plan to implement a feature, NOT implementing it yet
- Use your reasoning model: THINK HARD about the architecture and implementation approach
- Read the codebase to understand existing patterns, styles, and conventions
- Focus on the files in the Relevant Files section when designing the implementation
- Fill in EVERY section of the Plan Format - especially Testing Strategy
- Break the Implementation Plan into Foundation, Core, and Integration phases
- Include validation commands that prove the feature works end-to-end
- Consider edge cases and error scenarios in your planning

## Relevant Files

Focus on the following files to understand the codebase:

- README.md (project structure and conventions)
- CLAUDE.md (agent instructions if present)
- src/**or app/** (source code patterns to follow)
- tests/** (testing patterns and conventions)
- package.json or pyproject.toml (dependencies)
- docs/** (existing documentation style)

## Plan Format

Write the plan to `specs/feature-<descriptive-name>.md` using this exact format:

```markdown
# Feature: <descriptive-name>

## Feature Description
<Clear explanation of the feature and its value to users>

## User Story
As a <role>, I want <capability> so that <benefit>.

## Problem Statement
<What user need or pain point does this feature address>

## Solution Statement
<High-level description of how this feature solves the problem>

## Relevant Files
<Files to create or modify, organized by type>

### New Files
- <path/to/new/file.ts> (purpose)

### Modified Files
- <path/to/existing/file.ts> (what changes)

## Implementation Plan

### Foundation Phase
<Setup, dependencies, configuration, scaffolding>

### Core Phase
<Main feature implementation - the primary logic>

### Integration Phase
<Connecting components, wiring up, final touches>

## Step by Step Tasks
1. <First task with specific file references>
2. <Continue with numbered, specific tasks>

## Testing Strategy

### Unit Tests
<Component and function-level tests to write>

### Integration Tests
<Cross-component and API tests to write>

### Edge Cases
<Boundary conditions and error scenarios to test>

## Acceptance Criteria
- [ ] <Specific criterion that can be verified>
- [ ] <Another criterion>
- [ ] <Continue criteria>

## Validation Commands
<Commands that prove the feature works>
- Run `<test command>` to verify unit tests pass
- Run `<test command>` to verify integration tests pass
- Run `<build command>` to verify build succeeds
- Manual verification: <steps to manually test>

## Notes
<Future enhancements, related features, technical debt, dependencies>
```markdown

## Feature

$ARGUMENTS
