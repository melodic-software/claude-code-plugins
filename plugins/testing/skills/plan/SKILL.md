---
description: "Analyze code changes and produce a test plan. Classify changed files by required test type, identify coverage gaps, and prioritize by regression risk. Use when: 'test plan', 'what needs testing', 'where are the coverage gaps', 'what should I test here', after /implementation:implement completes, or for PR-prep coverage verification; for writing the tests use /testing:write, for running them /toolchain:check."
argument-hint: "[range or scope] (e.g., /testing:plan, /testing:plan HEAD~3, /testing:plan the auth module)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: test
  summary: Classify changes by required test type and coverage gaps
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`
- Recent commits, `git log --oneline -5`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 20 entries")
bounds nothing: the Bash tool returns the command's complete output into context before there is
anything to decide about.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git.

## Purpose

Coverage-gap analysis: what needs testing, at what level, and in what priority. Per-ecosystem test structure (frameworks, locations, architecture-test project) comes from the consuming project's testing conventions; infer from existing test projects when undocumented.

## Arguments

`$ARGUMENTS`, optional diff range or scope description. Default: uncommitted changes plus the current branch's commits vs the default branch.

## Process

### 1. Analyze the diff

```bash
git diff --stat HEAD~N   # or appropriate range
git diff --name-only HEAD~N
```

Classify each changed file:

| File type | Testing implication |
|-----------|-------------------|
| Domain entity / value object | Unit tests (behavior, invariants, state transitions) |
| Command/query handler | Unit tests (logic) + integration tests (DI, pipeline) |
| API endpoint | Integration tests (HTTP round-trip, status codes, response shape) |
| Middleware / filter | Integration tests via the ecosystem's HTTP-test harness (e.g. WebApplicationFactory for .NET) |
| Infrastructure (EF, external services, DB clients) | Integration tests with real infrastructure (Testcontainers / Docker Compose when available) |
| Configuration / DI registration | Integration tests (verify resolution, no runtime errors) |
| Project file / build infrastructure changes | Architecture tests (when the project has an architecture-test project) |
| UI components (Blazor, HTML, JS frameworks) | E2E testing via browser automation (see `/testing:run-e2e`) |
| Analyzer / lint rules | Analyzer tests (verify diagnostic output) |

### 2. Generate the test plan

For each change area, produce (test-name forms follow the project's documented pattern; when undocumented, mirror the ecosystem's idiom, the PascalCase placeholders below are illustrative (.NET/xUnit)):

```markdown
## Test Plan for [branch/PR description]

### Unit tests
- [ ] `{Method}_Should{Behavior}_When{Condition}` — {why this matters}
- [ ] ...

### Integration tests
- [ ] `{Subject}_{Behavior}` — {what this validates}
- [ ] ...

### Architecture tests
- [ ] {Rule}_Should{Constraint} — {if project structure changed}

### E2E verification (if UI/API changes)
- [ ] Navigate to {endpoint}, verify {behavior}
- [ ] Submit {form}, confirm {response}
- [ ] Screenshot: {page} showing {expected state}

### Not testing (with rationale)
- {File}: pure contract, no behavior to test
- {File}: covered transitively by {consumer test}
```

### 3. Gap analysis

Check existing tests against the plan:

- Are there test files covering the changed code?
- Do existing tests cover the new behavior, or only the old?
- Are architecture tests needed (project structure changes)?
- Would E2E testing catch something automated tests can't?

### 4. Prioritize

Not all gaps are equal. Prioritize by:

1. **Regression risk**. Changes to existing behavior that could break silently
2. **Business criticality**. Core domain logic > utility helpers
3. **Complexity**. Conditional logic, state machines, error paths
4. **Integration points**. Boundaries where components meet

## Output

Present the test plan to the user. Then suggest:

- `/testing:write` for identified unit/integration gaps. **For HIGH/CRITICAL coverage gaps**, the `advisor`-tool checkpoint (when available in the session) applies after the new tests land
- `/testing:run-e2e` for UI/API verification scenarios
- `/testing:write organize` if new test projects are needed

## What this skill does NOT do

- **Does not write tests**. `/testing:write`
- **Does not run tests**. `/toolchain:check` (SSOT for CLI invocation)
