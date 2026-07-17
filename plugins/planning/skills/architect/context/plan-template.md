# Plan Template

Scale to the task — not every section is needed for every plan. A trivial fix needs 3-5 bullets. A cross-cutting change needs the full template.

## Full Template

```markdown
## Goal

**What**: <1-2 sentences — what is being changed>
**Why**: <1-2 sentences — the motivation, not just "because we need to">

## Standards grounding

<which consumer standards shaped this plan — from the grounding step. Skipped at trivial/small scale: state "Skipped: <scale> scale, ambient context only">

| Surface | Sections cited | Layer provenance |
|---------|----------------|------------------|
| <surface id from the index> | <file + section(s) loaded> | <team / personal overlay / user-global> |

## Approach

### Steps

1. <Step with rationale>
2. <Step with rationale>
3. ...

### Files Affected

| File | Action | What changes |
|------|--------|-------------|
| `path/to/file.cs` | Modify | Add caching decorator |
| `path/to/new-file.cs` | Create | New cache configuration |
| `path/to/old-file.cs` | Delete | Replaced by new approach |

### File Inventory (when plan touches ≥10 files)

When a plan or phase touches ≥10 files, emit a checkbox inventory table. Checkboxes enforce verification discipline — the agent ticks each file as processed; the reviewer sees completeness at a glance.

| File | Action | Rationale |
|------|--------|-----------|
| [ ] `path/to/file.cs` | MODIFY | Add caching decorator |
| [ ] `path/to/new-file.cs` | CREATE | New cache configuration |
| [ ] `path/to/old-file.cs` | DELETE | Replaced by new approach |
| [ ] `path/to/keep-file.cs` | KEEP | Audited, no changes needed |

**Action vocabulary:** KEEP (audited, no change), MODIFY (edit content or frontmatter), CREATE (new file), DELETE (remove), MOVE (rename/relocate), MERGE (combine into another file).

**Location:** per-phase in the plan body, not a separate top-level section. Each phase lists only the files IT touches. Files appearing in multiple phases get a row in each.

**When to use KEEP:** include files audited and deliberately left unchanged — documents completeness ("we looked at this and it's fine") vs omission ("we forgot about this").

**Below threshold (<10 files):** the "Files Affected" table above is sufficient — no checkboxes needed.

### Dependencies

- <What this plan depends on — existing code, libraries, infrastructure>
- <What depends on this plan — downstream consumers, tests, CI>

### Pre-flight consumer check (when migrating a contract)

When a phase migrates a contract surface (frontmatter schema, JSON schema, public API, env-var shape, file format, exported function signature), list "Identify consumers" as the FIRST work item:

1. **Pre-flight (FIRST item):** `Grep` + `Glob` for scripts/hooks/workflows/sibling components parsing the contract surface. Document parse paths.
2. Migration work items follow.
3. Consumer-update work items (if pre-flight surfaces affected consumers).

Without pre-flight, migrations break consumers silently. Example: a frontmatter field migration must pre-flight scripts parsing the field via `yq` / `grep` / a YAML library.

## Alternatives Considered

| Alternative | Why rejected |
|-------------|-------------|
| <Approach A> | <Specific reason — not just "too complex"> |
| <Approach B> | <Specific reason> |

## Test Strategy

> **Invoke `/tdd:principles` (if installed) when writing this section** — it provides authoritative guidance on what to test, testing styles (output/state/communication), when to mock, and testable architecture patterns. Test-first (Red-Green-Refactor) is the default — specify test-after only when genuinely impractical.

- <How to verify the changes work — specific test types, not just "write tests">
- <TDD approach: which tests get written first, what assertions prove the behavior>
- <Bug fixes: name the regression test that fails pre-fix, or document an explicit carve-out with rationale>
- <Edge cases to cover>
- <Existing tests that need updating>

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| <What could go wrong> | Low/Med/High | Low/Med/High | <How to prevent or handle it> |
```

## Abbreviated Template (for trivial/small tasks)

```markdown
## Plan: <title>

**Goal**: <what and why in one line>

**Steps**:
1. <step>
2. <step>
3. <step>

**Test**: <how to verify>
```

## Choosing the Right Scale

The plan depth should match the blast radius:

- **Trivial** (typo fix, doc update, single-line config): abbreviated template, 3-5 bullets
- **Small** (new rule, simple feature, 2-5 files): abbreviated template with test strategy
- **Medium** (new library, module changes, 5-15 files): full template minus alternatives
- **Large** (architecture change, cross-cutting refactor, new service): full template + stress-test

Standards grounding follows the same scale: trivial and small plans skip the "Standards grounding" element (ambient context only — no standards fetch); medium and large plans include it for the surfaces they touch.

Calibration examples by scale:

- **Trivial** — fix a typo in a convention doc; bump an SDK version pin
- **Small** — add a new lint rule; introduce a single utility in an existing shared library
- **Medium** — a new shared library; add a cache to a query handler; a new module in a modular monolith
- **Large** — module extraction; auth-provider integration; a cross-cutting refactor touching multiple apps and libraries

When in doubt, err toward more detail. A plan that's "too detailed" wastes 30 seconds reading. A plan that's "too brief" wastes 30 minutes fixing assumptions.

## Script Repeatable Operations (default deliverable)

When any phase includes ≥3 sequential shell commands that could conceivably re-run (migrations, verifications, setup flows, audit sweeps, cleanup routines), the phase deliverable is a script (in the project's tooling directory, per its conventions), not copy-paste commands in PLAN.md.

**Plan body shows:** script flow (pseudocode), expected inputs/outputs, `--dry-run` behavior, rollback path. NOT the raw commands a user would type manually.

**Script conventions:** `--help` (usage), `--dry-run` (preview), idempotent re-run, a co-located test where the project's conventions call for one, lint-clean.

**Exceptions (manual steps acceptable):**

- Truly one-time + platform-interactive (GUI auth flows, hardware provisioning)
- ≤2 commands with no conditional logic (inline in PLAN.md is simpler)
- Commands that require human judgment at each step (no deterministic path)

**Anti-patterns:**

- A 10-step copy-paste sequence in a PLAN.md phase body (should be a script)
- "Run these commands in order" without error handling or prereq checks
- Migration docs that become stale after first use

## Sanity-Check Format (per-phase)

Every phase ends with at least one `**Sanity Check:**` bullet. Criteria MUST be mechanically verifiable — a specific grep, file Read assertion, build exit code, test exit code, or runtime probe a fresh cleared session can execute without inferential judgement.

**Verifiable format** (acceptable):

- `**Sanity Check:**` `grep -c "<pattern>" <file>` returns 0
- `**Sanity Check:**` build exit 0; tests exit 0 across <test projects>
- `**Sanity Check:**` `<file>` line N matches `<regex>`; `<file>` does NOT contain `<deprecated-pattern>`
- `**Sanity Check:**` the project's pre-commit hooks pass against a staged sample fixture

**Vague format (REJECTED — rewrite as verifiable):**

- ~~"Documentation looks appropriate"~~
- ~~"Code behaves as expected"~~
- ~~"All cases covered"~~
- ~~"Convention applied correctly"~~

When in doubt, surface the exact command a reviewer would run.

## Sub-Topic Promotion Trigger

Recommend promoting a phase to its own topic directory (with its own PLAN.md) when it exhibits ANY:

- >5 distinct work items
- >300 LOC delta estimate
- Own exploration or research need (the phase has its own external research questions)
- 2+ sub-phases of its own (the phase has internal structure that wants its own PLAN section)
- Independent commit boundary (the phase produces a separately-mergeable PR-shaped chunk)

Sub-topics keep the parent PLAN.md scannable and give the promoted work its own clean-context boundary. A sub-topic PLAN.md inherits the parent PLAN structure (Brief, Plan sections recursively).

## Execution-Shape Analysis

For plans with ≥2 phases. Single-phase plans and trivial fixes skip this section entirely — skipped = all-main-session execution, stated in one line.

### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 1.1 | <files> | <other phases sharing files, or "none"> |
| 1.2 | <files> | <other phases sharing files, or "none"> |
| 1.N | <files> | <other phases sharing files, or "none"> |

### Dependency graph

- <Phase A → Phase B because B reads A's output / cites A's contract change>
- <Phase C activates a hook that affects Phase D's commit>
- <Phase E is independent of A, B, D>
- (or one-liner: "all phases sequential — semantic-source-first ordering")
- Integration-first ordering — a third axis beyond dependency-order and parallelism: among phases not forced by a dependency, the integration slice goes first.

### Recommended shape

**Sequential** (when phases share files OR have chain dependencies):

> Fully sequential: 1.1 → 1.2 → 1.3 → ... — <one-line rationale, e.g. "1.2 sweep state required clean before 1.3 detector activates">

**Parallel** (when ≥2 phases are file-disjoint AND the independent work is material):

> Wave A (parallel sub-agents, single message): {phases}
> Wave B (sequential after Wave A returns): {phases}
> Cost note: N parallel agents multiply token usage vs sequential — the user picks consciously

### Scope-fencing tables (required if parallel recommended)

Each agent gets an explicit ALLOWED whitelist + FORBIDDEN deny-list:

| Agent | Phase | ALLOWED files | LOC |
|---|---|---|---|
| A1 | 1.X | <whitelist> | <est> |
| A2 | 1.Y | <whitelist> | <est> |

**Each agent FORBIDDEN:** any file outside its ALLOWED list; PLAN.md (main session edits status only); other agents' territory; staging/commit/push operations (handled per the consuming project's own commit policy).

**Each agent reports at end:** work items completed + per-criterion Sanity Check verdict + actual LOC delta.

**Divergence escalation (copy into every worker brief verbatim):**

```text
DIVERGENCE ESCALATION (mandatory): if reality diverges from this brief —
a precondition fails, a file/symbol named here is absent or different than
described, scope is blocked, or a design question arises mid-task — STOP.
Do not improvise, fix forward, or expand scope. Report to the orchestrator:
what you found, what the brief expected, and the exact state of your work
(files touched, edits applied / not applied). Await a revised brief.
```

### Sequential fallback (document inline)

Document a one-line fallback path if parallel orchestration fails:

> If a scope-fence violation OR concurrent-edit race OR an agent reports cannot-complete, abort that agent + fall back to sequential N → M → ... for the affected phase only. Other parallel agents continue.

### Per-phase routing table

Assign each phase an execution surface:

| Phase | Surface | Basis |
|---|---|---|
| <N> | <main-session / sub-agent worker> | <one-line task-shape rationale> |

- **Main-session** — judgment-heavy, tightly coupled to conversation context, or requires user interaction
- **Sub-agent worker** — mechanical, file-disjoint volume work that returns a summary; every worker row implies a dispatch brief carrying the scope fence + the divergence-escalation clause above

## Large-scale changes (migrations, library swaps, broad refactoring)

When the plan involves changes across many files (10+), library migrations, or API replacements, include these additional planning dimensions:

### Discovery scan

Before planning the approach, inventory the full scope:

- Grep for all usages of the old pattern/library/API across the codebase
- Count affected files and classify by ecosystem
- Identify documentation that references the old pattern (plan a post-migration doc sweep to catch stragglers)

### Execution strategy

| Scenario | Strategy |
|----------|----------|
| Uniform, repetitive changes (same transform across many files) | Parallel sub-agent workers with scope fences |
| Complex changes requiring judgment per file | Sequential implementation with per-file commits |
| Mixed — some uniform, some complex | Hybrid — parallel for the uniform part, sequential for the rest |

### Post-implementation quality passes

The plan should capture migration-specific inputs the downstream quality passes will need:

- Whether documentation needs a sweep (did the migration rename APIs, libraries, or patterns?)
- What grep pattern to use for the **completeness check** (remnants of the old pattern are bugs, not TODOs)

### Tidy First discipline

Per Kent Beck: separate structural commits (renames, extracts, reorganizations) from behavioral commits (new features, API changes). This applies especially to large migrations — the structural scaffolding commit should be reviewable and revertable independently from the behavioral changes.

## Phase Review tags (optional per phase)

When a phase touches a review concern that should be caught at the phase boundary (not deferred to PR), add a `Review:` line immediately under the phase header. Implementation dispatches a fresh-context sub-agent review before the phase commit.

```markdown
### Phase N: <name> [TODO]
Review: architecture   # structural integrity, dependency direction
Review: security       # auth, input handling, secrets
Review: concurrency    # races, shared state
Review: code-design    # configurability, testability, observability
```

Omit `Review:` when the phase is docs-only or trivial with no new types/contracts.

## Phase-entry checks for tracker writes

When any phase ends in creating a work item (e.g. `gh issue create`), the plan body MUST structure that phase so the create call cannot dispatch without first verifying no duplicate exists. The pivot path (comment on the existing item) MUST be listed explicitly — not deferred to runtime judgement.

Required phase shape:

````markdown
### Phase N: <name>

- [ ] **Phase-entry check** (first work item — verifies no duplicate exists):

  ```bash
  gh issue list --state all --search '<key-term> in:title' --json number,title,state
  ```

- [ ] **If search returns a match** → pivot: `gh issue comment <N> --body '<...>'` instead of creating a duplicate. Skip the remaining create steps; close the phase with the comment URL as evidence
- [ ] **If search returns empty** → proceed with create:

  ```bash
  gh issue create --title '<title>' --body '<body>' --label '<label>'
  ```

- [ ] **Sanity Check:** the item number (newly created OR pivoted-to) recorded in the phase notes; URL captured
````

`gh pr create` does NOT need an equivalent phase-entry check — it errors out on branches that already have an open PR, so duplicates are structurally prevented.

## Checkbox inventory pattern

When a plan involves moving, renaming, or modifying a GROUP of files (batch migrations, directory reorganizations, rename sweeps), emit per-file checkbox inventories per phase:

```markdown
### Phase N: <slice name>

**File moves:**
- [ ] `git mv old/path/file.sh new/path/`
- [ ] `git mv old/path/file.test.sh new/path/`

**Reference updates:**
- [ ] `consumer-a.sh` — source path updated
- [ ] `consumer-b.md` — documentation ref
- [ ] `.github/workflows/ci.yml` — CI path trigger

**Sanity Check:**
- [ ] `grep -rn 'old/path/file' --include='*.sh' --include='*.md' .` returns empty
- [ ] the project's test suite passes
```

**When to use:** the plan involves ≥3 files being moved/renamed AND each file has downstream references requiring update. Checkbox granularity = one box per file move + one box per reference-update site + one box per sanity-check criterion.

**Why:** mechanical refactors across many files have high "forgot one reference" risk. Per-file checkboxes make progress trackable across cleared-context boundaries and make sanity-check grep patterns explicit. Implementation ticks boxes as work completes.

## Domain-specialist skills during planning

When the plan touches a domain with a dedicated installed skill or plugin (cloud deployment, AI/ML library selection, edge compute, MCP server design, project scaffolding), cite that skill's slash invocation for deeper analysis during planning and stress-testing rather than reasoning from general knowledge. Enumerate what is actually installed; do not assume a roster.
