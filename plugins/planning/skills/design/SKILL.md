---
name: design
description: "Explore and resolve design decisions — types, contracts, package topology, module boundaries — through collaborative discussion rounds before /planning:plan plans implementation, producing capability-matrix / type-inventory / design-threads / topology artifacts. Use for 'design this', 'type modeling', 'figure out the abstractions', 'model this domain', or entering /planning:plan without exploring the design space first; scales from a single-file early-exit to a multi-session design effort."
argument-hint: "[scope] [action] (e.g., /planning:design library, /planning:design module, /planning:design status, /planning:design discuss, /planning:design handoff)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Design exploration answers WHAT before `/planning:plan` answers HOW. Without it, implementation plans are built on unexamined assumptions — the wrong types, wrong boundaries, wrong package topology. This skill structures the exploratory work so that every `/planning:plan` plan starts from a design the user has validated through iterative discussion.

This is the step between research and planning: exploration maps existing code, research gathers external facts, this skill synthesizes both into a concrete design, and `/planning:plan` plans implementation of that design. Upstream: when the PROBLEM itself is still rough — no chosen approach to design — diverge first via `/brainstorm` (cheapest→most-ambitious candidates, user reacts), then design the direction that resonated.

The depth of design exploration scales to the work:

- Single-file fix → early-exit: write `design-resolution.md` with `outcome: early-exit`, tier `C`, and reason — then proceed to `/planning:plan`
- New module → light-form (1-2 discussion rounds, basic type sketch)
- Large library or system → full-form (multiple sessions, all phases, all artifact types)

Early-exit is diagnostic, not failure. The stage always runs; depth scales to signal. **Gate artifact:** Tier C and light Tier B early-exits MUST produce `design-resolution.md` in the topic's design slice (`<contract_dir>/<topic-slug>/design/`, default `docs/topics/`; the memory slice under `contract_tier: local`) so `/planning:plan`'s prerequisite check can verify the gate without relying on conversation memory.

### design-resolution.md (early-exit artifact)

Minimal frontmatter + body when full design exploration is not required:

```markdown
---
outcome: early-exit
tier: C
reason: <one line — e.g. single-file bugfix, docs-only>
---

Optional: type sketch pointer if tier B — link to type-inventory.md
```

## Action Router

Parse `$ARGUMENTS` for scope and action:

| Argument | Action |
|----------|--------|
| *(empty)* | **Auto-detect** — read the PLAN.md Brief + conversation context to determine scope and current phase. Resume if design artifacts exist. Ask if ambiguous |
| `library` | **Library/API design** — packages, types, contracts, dependency graph |
| `module` | **Module design** — domain model, boundaries, contracts. Suggest a domain-event workshop (e.g. EventStorming) for domain event discovery when the environment provides one |
| `data` | **Data model design** — entities, relationships, schema decisions |
| `integration` | **Integration design** — cross-system contracts, sequence flows, error handling |
| `system` | **System design** — components, communication patterns, deployment topology |
| `status` | **Status report** — show resolution state per thread and question |
| `thread <name>` | **Deep-dive** — focus on one specific design thread |
| `discuss` | **Discussion round** — systematic gap-finding across all artifacts |
| `terminology` | **Naming review** — cross-cutting naming pass over the full type inventory (see "Terminology pass") |
| `handoff` | **Handoff gate** — in-session shortcut; delegates to `/planning:design-handoff` (see "Handoff gate") |

## Phases

Design exploration is iterative, not strictly sequential. Phases may interleave. Track which phases have produced artifacts and which have outstanding questions.

All artifacts live in `<contract_dir>/<topic-slug>/design/` (default `docs/topics/`) — the topic's contract slice, committed on the task branch (under `contract_tier: local` it joins the memory slice): the gate files (`design-threads.md`, `design-resolution.md`) and the working design exploration docs travel together, because `/planning:plan`'s gate and any fresh worktree or clone must see them. Roots, tier, and precedence resolve per the topic-docs binding [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md). Derive `<topic-slug>` from the task or branch name (kebab-case, ≤40 chars; shared with `/interview` and `/planning:plan`). Skip artifact creation for read-only actions (`status`).

### Phase 1: Problem Space Decomposition

Break the domain into capabilities or concerns. For each one:

- Domain concepts (nouns, verbs, relationships)
- Invariants (rules that must always hold)
- Storage needs (stateless? persistent? app-specific?)
- Cross-app reuse potential — decide shared-library-worthy vs app-specific per capability, following the consuming project's own library-organization and dependency-preference conventions when it declares them

Produce: `capability-matrix.md` (library scope) or equivalent per scope.

Survey-then-deep: broad scan of the problem space before diving into any single capability.

### Phase 2: Design Threads

Identify cross-cutting design decisions that affect multiple capabilities. For each thread:

- Name the decision
- List concrete options with tradeoffs
- Resolve through discussion or defer with rationale + research tag

Track resolution status: **resolved** (decision made), **directional** (direction agreed, details deferred), **deferred** (needs research).

For SaaS or B2B org-scoped products, open a **tenancy posture** thread early: single- vs multi-tenant, isolation model, shared vs tenant-scoped data catalog.

When exploration surfaces high coupling, large types, or multi-responsibility files (refactor or strangler scope), open a **refactoring posture** thread: characterization-test strategy, seam map, incremental extract order, change budget.

For any feature with a testable surface, open a **test-seam posture** thread: sketch the seams the feature will be tested at. Prefer existing seams over new ones; place any new seam at the highest level possible; drive toward the fewest seams that cover the surface — the ideal count is one. Confirm the seam sketch with the user before design output is finalized.

Produce: `design-threads.md`

### Phase 3: Type Modeling

Derive types from capabilities:

- Records, enums, strongly-typed IDs, value objects
- Contracts: interfaces with method signatures
- Follow the consuming project's naming conventions (interface naming, context-relative naming, name-collision avoidance with common library types, namespace conventions) — read its rules before naming
- Follow the project's codified design principles (e.g. Law of Demeter, dependency direction, disambiguating overloaded terms) where it declares them; otherwise apply standard low-coupling/high-cohesion defaults
- Invoke `/domain-driven-design:ubiquitous-language` the moment a domain term resolves so the
  active glossary owner applies the consumer's existing format, placement, and context routing

Produce: `type-inventory.md`

Once type modeling stabilizes, run the `terminology` action for the cross-cutting naming review of the full inventory — per-type naming during modeling is not a substitute for the whole-inventory pass.

### Phase 4: Package/Module Topology

Define the structural layout:

- Package or module structure with dependency graph
- What goes where (abstractions vs implementation vs service defaults)
- Adapter surfaces (infrastructure boundary)
- Dependency direction enforcement per the project's declared layer rules

Produce: `library-topology.md` (library scope) or equivalent per scope.

When the dependency graph reads more clearly visually than in markdown, optionally also emit a self-contained HTML topology view alongside the markdown (which stays the tracked record).

### Phase 5: Discussion Rounds

Systematic gap-finding. For each round:

1. Re-read all design artifacts
2. Identify underspecified types, missing contracts, boundary friction, pattern concerns, and design-default gaps (configurability, extension axes, observability, testability) — record these as design threads
3. Present findings to user for discussion
4. When discussion surfaces project-wide principles, suggest codifying them immediately in the project's own rules

Continue rounds until no new gaps surface — then run the `handoff` action to delegate to `/planning:design-handoff` for the binary gate and plan-ready summary.

## Terminology pass (`terminology` action)

A cross-cutting naming review of the full type inventory, run once type modeling stabilizes:

1. Check interface-naming form and context-relative naming against the project's conventions
2. Check collisions with common library/framework type names (e.g. a bare `Result<T>` when the stack already ships one)
3. Check overloaded-term disambiguation and domain accuracy against the project's domain vocabulary
4. Record decisions in a terminology table inside `type-inventory.md`
5. Invoke `/domain-driven-design:ubiquitous-language` to sync resolved terms and rejected synonyms
   into the consuming project's active glossary

## Handoff gate (`handoff` action)

The in-session shortcut to the design→plan gate. Delegate to `/planning:design-handoff` — the single canonical gate implementation: it applies the binary check against `design-threads.md` (or the `design-resolution.md` early-exit artifact), and on PASS emits the plan-ready summary and resume prompt. This skill carries no gate criteria of its own; criteria changes land in `/planning:design-handoff` only.

## Scope-specific artifacts

| Scope | Primary artifacts |
|-------|-------------------|
| `library` | capability-matrix.md, type-inventory.md, library-topology.md, design-threads.md |
| `module` | domain-model.md, module-boundary.md, contracts.md, design-threads.md |
| `data` | entity-relationships.md, schema-decisions.md, design-threads.md |
| `integration` | contract-spec.md, sequence-flows.md, design-threads.md |
| `system` | component-map.md, communication-patterns.md, design-threads.md |

`design-threads.md` is common across all scopes — cross-cutting decisions always arise.

## Key behaviors

- **Collaborative always.** Never autonomously decide design. Ask in frontier rounds — every open thread whose prerequisites are settled surfaces in the same numbered round, each with a recommendation; a thread that depends on an unresolved thread waits for the round after it resolves. Render a round via `AskUserQuestion` only when the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`) is on and the round is ≤4 independent questions — inline prose otherwise
- **Track resolution status.** Every question and thread gets a status: resolved / directional / deferred. Deferred items carry a research tag describing what external investigation is needed
- **Codify rules when discovered.** When discussion surfaces a principle that applies project-wide, suggest codifying it immediately in the project's own rules files
- **Incremental artifacts.** Don't produce all artifacts at once. Build them as discussion progresses. Update existing artifacts as decisions evolve. Multi-turn shared artifacts (`design-threads.md` and peers): re-read from disk before every write — another turn or agent may have modified them — and prefer appending or refining over wholesale rewrites
- **Dependency order awareness.** Note which decisions block others. Surface these dependencies to the user so `/planning:plan` can sequence phases correctly
- **Resume from prior state.** When design artifacts exist in the topic's design directory, resume from them. Read artifacts, summarize current state, identify remaining gaps
- **Suggest adjacent skills.** When a domain-event workshop fits better for domain modeling, suggest it if available. When external research is needed for a deferred item, suggest the research capability (`/discovery:research` if installed). When the session tail is reached, suggest the `terminology` then `handoff` actions
- **Design defaults (non-trivial scopes only).** For `library`, `module`, `data`, `integration`, and `system` scopes — when discussion touches configurability, extension points, observability, or testability, open a design thread for it. Skip on early-exit, `status`, or trivial single-file work

## What this skill does NOT do

- **Implementation planning** — that's `/planning:plan` (phases, sanity checks, file-level work items)
- **Code writing** — that's the implementation stage
- **External research** — that's the research capability (this skill synthesizes research results into design decisions)
- **UI/UX design** — use dedicated frontend design and UI/UX tooling
- **Domain event workshops** — a dedicated EventStorming-style capability covers that methodology; this skill covers broader design and may suggest it within module design
- **Product intent** — that's `/prd` (problem, users, success metrics)
- **Intent contract** — that's `/interview` (goal, constraints, acceptance criteria)

## Relationship to other skills

| Skill | Relationship |
|-------|-------------|
| `/interview` | **Before.** `/interview` locks the brief (scope + constraints). `/design` explores the solution space within those constraints |
| `/domain-driven-design:ubiquitous-language` | **During.** Owns active project-glossary updates whenever design resolves domain language; it does not own type or boundary design |
| `/discovery:explore` (if installed) | **Before.** Exploration maps existing code. `/design` creates what SHOULD exist |
| `/discovery:research` (if installed) | **Before + parallel.** Research gathers external facts. `/design` synthesizes them. Deferred research items can run in parallel |
| `/design-handoff` | **The gate.** Owns the design→plan gate criteria and the plan-ready summary; this skill's `handoff` action delegates to it |
| `/planning:plan` | **After the handoff gate.** `/design` produces WHAT. `/planning:plan` produces HOW (implementation plan with phases). When design artifacts exist, `/planning:plan` consumes them instead of re-deriving design inline |
