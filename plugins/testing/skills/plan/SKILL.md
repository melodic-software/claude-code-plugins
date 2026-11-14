---
description: "Analyze code changes and produce a test plan. Classify changed files by required test type, identify coverage gaps, and prioritize by regression risk. Use when: 'test plan', 'what needs testing', 'where are the coverage gaps', 'what should I test here', after /implementation:implement completes, or for PR-prep coverage verification; for writing the tests use /testing:write, for running them /toolchain:check."
argument-hint: "[range or scope]"
user-invocable: true
disable-model-invocation: false
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

The pipe is the bound and belongs in the command: a read-time cap ("read only the first 20
entries") comes too late for whatever the command has already returned inline. What a result
returns inline, and when it arrives as a saved file instead, is [Tools reference § Output limits](https://code.claude.com/docs/en/tools-reference#output-limits).

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines, one command per call. The dated record for
why is the
[gather-block convention § The pre-compute block runs as one shell invocation](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation). How injected commands run is
[Extend Claude with skills § How injected commands run](https://code.claude.com/docs/en/skills#how-injected-commands-run).

## Purpose

Coverage-gap analysis: what needs testing, at what level, in what priority. Per-ecosystem test
structure (frameworks, locations, architecture-test project) comes from the consuming project's
testing conventions; infer it from existing test projects when undocumented.

## Arguments

`$ARGUMENTS`, optional diff range or scope description. Default: uncommitted changes plus the
current branch's commits vs the default branch.

Examples: /testing:plan, /testing:plan HEAD~3, /testing:plan the auth module.

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
| Parser, serializer, pure transform, collection or stateful class | Property tests beside examples (invariants from the spec, a model or metamorphic relation; see `/testing:write`) |
| Replace, rewrite, migrate or port of existing behavior | Characterization or differential tests first (old output as a pin, intentional differences in a ledger; see `/testing:write`), then the usual rows for the new code |
| Parser, decoder or handler whose input is untrusted (request bodies, uploaded files, hook or webhook payloads, CLI arguments from another process) | Fuzz target: generated and mutated inputs fed to the entry point, asserting no crash, hang, unbounded resource use or failure other than the documented rejection, with a seed corpus of valid inputs; a parser matching the property row too gets both |
| Client of a service whose provider will run the verification, or an endpoint another service consumes | Consumer-driven contract test: the consumer records the requests it sends and the responses it relies on, and the provider's build verifies it still meets them. A public third-party API's provider runs none: plan its canned responses per `testing:test-value` (if enabled) instead |

### 2. Generate the test plan

When step 1 found no changed file in the range, nothing is planned: say there is nothing to
classify and end there, skipping the rest of this process and the Output suggestions, with no
template section and no test type named as considered or skipped.

For each change area, produce the plan below. Omit a fuzz-target or contract-test section when no
changed code matches its row: do not print it empty, write it as "none", or list it under "Not
testing".

Test names follow the project's documented pattern; when undocumented, mirror the ecosystem's
idiom (the PascalCase placeholders are illustrative, .NET/xUnit):

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

### Property tests (if parsers, serializers, transforms or stateful classes changed)
- [ ] {Property stated from the spec} — {pattern: model, metamorphic, round trip}

### Pins (if replacing or migrating behavior)
- [ ] {Behavior pinned} — {recorded corpus, comparator, intentional-differences ledger}

### Fuzz targets (only if code whose input is untrusted changed; otherwise omit this section)
- [ ] {Entry point} — {input shape, seed corpus, what must not happen: crash, hang, unbounded memory}

### Contract tests (only if a service client or consumed endpoint changed; otherwise omit this section)
- [ ] {Consumer} → {provider interaction} — {requests sent, response fields relied on, where the provider verifies it}

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

Prioritize gaps by:

1. **Regression risk**. Changes to existing behavior that could break silently
2. **Business criticality**. Core domain logic > utility helpers
3. **Complexity**. Conditional logic, state machines, error paths
4. **Integration points**. Boundaries where components meet

## Output

Present the test plan to the user. Then suggest:

- `/testing:write` for identified unit/integration gaps. **For HIGH/CRITICAL coverage gaps**, the `advisor`-tool checkpoint (when available in the session) applies after the new tests land
- `/testing:run-e2e` for UI/API verification scenarios
- `/testing:write organize` if new test projects are needed

For each planned test, name where its expected value will come from: `testing:test-value` (if
enabled).

## Next

/testing:write

Writes the tests the plan names.

## What this skill does NOT do

- **Does not write tests**. `/testing:write`
- **Does not run tests**. `/toolchain:check` (SSOT for CLI invocation)
