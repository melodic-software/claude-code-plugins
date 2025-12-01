# Operational Rules

This document contains core operational guidelines for working with this repository, covering temporary file handling, error handling, workflow management, and platform awareness.

For detailed guidance on specific topics, see:

- **Path Conventions**: `.claude/memory/path-conventions.md`
- **Script Automation**: `.claude/memory/script-automation.md`
- **Agent Usage Patterns**: `.claude/memory/agent-usage-patterns.md`
- **Context Engineering**: `.claude/memory/context-engineering.md`

## Temporary File Management

### Temporary Workspace: `.claude/temp/`

Store all temporary files, agent handoffs, research artifacts, and scratch work in `.claude/temp/`.

**Purpose:**

- Agent-to-agent communication (passing context between agents)
- Research artifacts and exploration notes
- Draft content before final placement
- Scratch files for complex multi-step workflows

**Organization:**

Use a flat directory structure with descriptive naming convention:

```text
.claude/temp/
  ├── 2025-01-09_143022-explore-git-config.md
  ├── 2025-01-09_150000-plan-refactor-docs.md
  ├── 2025-01-09_151530-research-nodejs-versions.md
  └── 2025-01-09_160000-draft-new-skill.md
```

**Naming Convention:**

```text
YYYY-MM-DD_HHmmss-{agent-type}-{topic}.md
```

- `YYYY-MM-DD_HHmmss`: UTC timestamp in ISO 8601 date format with compact time (enables chronological sorting)
- `{agent-type}`: `explore`, `plan`, `general`, `research`, `draft`, etc.
- `{topic}`: Brief description of the task/topic (kebab-case)

**Lifecycle:**

- **Created:** When agents need to pass information or store temporary research
- **Used:** Read by subsequent agents or main conversation
- **Cleaned:** Periodically removed (these are ephemeral, not committed to repo)
- **Gitignored:** Already ignored via `.gitignore` rule

**Anti-Patterns:**

- Storing temp files in root directory or topic folders
- Using generic names like `temp.md` or `notes.md`
- Creating subdirectories within `.claude/temp/`
- Committing temp files to version control

### Cleanup Requirements for Non-Gitignored Temporary Files

Clean up any temporary files, test scripts, or artifacts created outside `.claude/temp/` that are not gitignored before considering a task complete.

**Cleanup Rules:**

- `.claude/temp/` files may persist (already gitignored)
- Files explicitly added to `.gitignore` may remain if intentional
- Remove temporary test files in repo root or topic folders
- Remove temporary scripts created for one-time testing
- Remove draft files, experimental code, or scratch artifacts

**Verification Before Completion:**

Before marking any task complete, run:

```bash
git status
```

Check for untracked files that are:

- Not in `.claude/temp/`
- Not listed in `.gitignore`
- Temporary or experimental in nature

**Rationale:**

- **Repository cleanliness**: Prevents accumulation of clutter
- **Version control hygiene**: Only intentional files should be tracked
- **Team collaboration**: Other developers don't see your temporary artifacts
- **Professional standards**: Clean repositories reflect quality standards

## Error Handling and Recovery

### Actionable Error Messages

Provide actionable error messages and recovery paths:

- When errors occur, explain what went wrong and why
- Provide specific, actionable steps to resolve issues
- Never fail silently - surface problems clearly
- Support undo/rewind for recoverable mistakes
- Include verification steps after fixes
- Log errors for debugging when appropriate

Good error handling isn't just about catching exceptions - it's about helping users understand and recover from problems. Error messages should guide toward solutions.

## Workflow and Task Management

### Task Decomposition and Incremental Progress

Break complex tasks into manageable steps with visible progress:

- Start with high-level understanding before making changes
- Break large tasks into smaller, testable increments
- Create checkpoints/save points before major changes
- Allow users to interrupt and course-correct at any phase
- Show progress and intermediate results
- Verify each step before proceeding to the next

Complex tasks should be decomposable. Users should be able to intervene at any point. Incremental progress with feedback loops produces better outcomes than monolithic execution.

### Plan Before Execute

For complex changes, create a plan before execution:

- Offer "plan mode" for complex multi-file changes
- Analyze codebase with read-only operations before proposing changes
- Present a plan for user review before executing
- Allow iterative refinement of the plan
- Separate planning phase from execution phase
- Use planning for exploration, code review, and research tasks

For complex tasks, planning before execution improves outcomes. Read-only exploration prevents accidental changes during analysis.

### Parallelization and Agent Usage

For guidance on when and how to use Task agents, parallelization strategies, model selection, and agent best practices, see `.claude/memory/agent-usage-patterns.md`.

**Key principle:** Before executing plans with multiple tasks, verify parallelization opportunities. Parallelizing independent tasks improves efficiency and reduces overall execution time.

### Context Management

For guidance on context window management, structured note-taking, compaction strategies, and hierarchical memory management, see `.claude/memory/context-engineering.md`.

**Delegation:** For Claude Code memory system guidance (CLAUDE.md files, memory hierarchy, import syntax, best practices), invoke the `memory-management` skill.

## Tool Usage Enhancements

### Tool Optimization Principles

When designing tools for agents, follow principles for effective tool design:

**Key principles:**

- Return meaningful context - prefer natural language names over cryptic IDs
- Optimize for token efficiency (pagination, filtering, truncation)
- Consolidate functionality - one tool can handle multiple operations efficiently
- Choose right tools for agents (consider context limits vs traditional software design)
- Namespace tools to avoid confusion (prefix/suffix-based grouping)
- Design helpful error messages (actionable guidance, examples)

**For comprehensive tool design guidance**, see `.claude/memory/tool-optimization.md` - covers choosing right tools, returning meaningful context, token efficiency, namespacing, error message engineering, and evaluation-driven improvement.

## Platform and Environment

### Platform and Environment Awareness

Adapt to different platforms and environments gracefully:

- Detect and adapt to platform-specific differences
- Provide platform-specific guidance when needed
- Support cross-platform workflows where possible
- Handle environment variables and configuration hierarchically
- Respect platform conventions (paths, commands, permissions)
- Provide fallbacks when platform-specific features are unavailable

Cross-platform systems must account for environmental differences. Don't assume a specific platform unless you know it. Provide graceful degradation.

### Graceful Degradation and Fallbacks

Provide fallback behavior when preferred options are unavailable:

- Detect when features/tools are unavailable
- Provide alternative approaches when primary fails
- Warn users when using fallback behavior
- Support gradual feature detection (not all-or-nothing)
- Allow users to configure fallback preferences
- Fail gracefully with clear error messages

Robustness requires handling edge cases. Systems should degrade gracefully rather than failing completely when conditions aren't ideal.

### Consistency and Conventions

Follow consistent patterns and naming conventions:

- Use consistent naming patterns (e.g., kebab-case for files)
- Follow established conventions in the domain
- Maintain parallel structure across similar components
- Use descriptive names that indicate purpose
- Document conventions so they're discoverable
- Normalize names for consistency

Consistency reduces cognitive load. When patterns are predictable, users learn faster and make fewer mistakes.

## Delegation and Specialization

### Contextual Adaptation and Intelligent Delegation

Adapt behavior based on task context; delegate when specialized expertise is needed:

- Recognize when a task requires specialized knowledge or tools
- Delegate to specialized agents/skills when appropriate
- Maintain separate context windows for independent tasks
- Use task-specific configurations (tools, prompts, models)
- Automatically invoke specialized capabilities based on task description
- Compose multiple specialized capabilities for complex workflows

Specialization improves outcomes. Recognize when general capabilities are insufficient and delegate to focused expertise. Context isolation prevents interference between independent tasks.

## Summary

**Temporary Files:**

- Use `.claude/temp/` for all scratch work
- Follow naming convention: `YYYY-MM-DD_HHmmss-{agent-type}-{topic}.md` (UTC timestamps)
- Flat structure, no subdirectories
- Ephemeral (not committed)

**Detailed Guidance:**

- **Path Conventions**: `.claude/memory/path-conventions.md`
- **Script Automation**: `.claude/memory/script-automation.md`
- **Agent Usage**: `.claude/memory/agent-usage-patterns.md`
- **Context Engineering**: `.claude/memory/context-engineering.md`
- **Tool Optimization**: `.claude/memory/tool-optimization.md`

Following these operational rules ensures consistency, portability, and efficiency in working with this repository.

**Last Updated:** 2025-11-30
