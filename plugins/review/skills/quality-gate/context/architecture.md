# Architecture review mode

Delegates to this plugin's `architecture-guardian` agent for architectural compliance review. Use when changes touch module boundaries, dependency direction, or structural patterns.

## When to use

- Adding new projects, packages, or modules
- Modifying project/package references
- Creating cross-module interactions
- Adding new aggregates, domain events, or shared contracts
- Refactoring module boundaries or slices
- Before PRs touching architecture-significant code

## How to invoke

Launch the `architecture-guardian` agent with:

- **Scope**: the changed files and their architectural context
- **Focus**: specific concerns surfaced during self-review or implementation
- **Input**: the review diff base (SKILL.md "Shared inputs") or specific file paths

The agent reads the project's own architecture docs first, then checks dependency direction, boundary integrity, abstraction quality, and pattern compliance (see the agent definition for the full baseline).

## After the review

- **Dependency violations**: fix before proceeding; they cascade into hard-to-diagnose problems
- **Pattern issues**: fix small or medium ones and file only a structural one that needs its own planning pass. A fix about the task, or an unrelated one in a file this change already touches, goes in this change as its own commit; any other unrelated fix goes in its own small PR with no tracker item, and a lane that cannot open a PR reports it, leaving any review thread on it unresolved. A project changes this placement in its own CLAUDE.md or AGENTS.md; the rule's owner is the D4.6 scope test in the source-control plugin's `reference/review-discipline.md` <!-- contract-restatement: D4.6-unrelated-fix-placement -->
- **Missing abstractions**: evaluate whether this is a real extensibility need or speculative (YAGNI)
- **Structural rules under test**: when the project has architecture tests (e.g. dependency-rule test suites), run them; they catch structural rules mechanically
