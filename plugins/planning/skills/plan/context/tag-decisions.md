# Tag unilateral decisions (Step 4.6)

Full taxonomy for `/planning:plan` Step 4.6. Before Step 5 approval, walk the PLAN body + Handoff section and classify every decision NOT explicit in the brief. Three categories:

| Category | Definition | Tag |
|---|---|---|
| **Briefed** | The Brief / interview locked this decision (acceptance criteria, constraints, out-of-scope items, deferred questions with `arbiter: /planning:plan`) | (no tag — assumed approved) |
| **Execution-shape** | /planning:plan's discretion within briefed scope — orchestration shape (parallel/sequential), sub-topic promotion, technique selection, per-phase ordering, sanity-check criteria | **Tag: `[EXEC-SHAPE]`** in the PLAN body |
| **Fallback-for-edge-case** | A /planning:plan-invented contingency for scenarios the brief did NOT anticipate — follow-up work items, alignment-check protocols between parallel agents, retry mechanisms, mid-flight pivot defaults | **Tag: `[FALLBACK — confirm or override]`** in the PLAN body |

## Confidence gate (decide vs interview)

A tag does NOT license deciding. Each `[EXEC-SHAPE]` / `[FALLBACK]` candidate passes the confidence gate first:

- **DECIDE (and surface)** only when the basis is evidence captured this session — a codebase pattern read, a research finding, or a directly-on-point project convention — AND no reasonable alternative survives that evidence.
- **INTERVIEW** everything below that bar: queue it and run an interview round (one question at a time, recommendation + basis) BEFORE the plan body locks. Judgment calls, sizing guesses, taste-based placement, and "either would work" choices are below the bar by definition.

**Reversibility ceiling on discretion:** a decision that is risky or hard to reverse later (new public contract, irreversible deletion, architecture-shaping placement, dependency adoption) does NOT qualify for deciding regardless of confidence — escalate to `/interview me` (relentless mode) EARLY, before dependent plan work is authored, leading with the best-practice long-term default (never a hack or workaround). Tags cover only decisions cheap to change after the fact.

**Complex/contested clusters** (3+ interacting decisions, or any the user pushed back on before) route to `/devils-advocate` before presenting.

## Presentation contract (Step 5)

Surface every decided tag at Step 5 in a "Decisions made (gate-passed)" subsection — a TABLE, not a bulleted label list:

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| <one line> | <phase + concrete delta — what the reader would diff> | <source read this session> |

The what-it-changes column is mandatory — a label without its plan impact is unreviewable. Write for a cold reader dropping in mid-session: no session-internal shorthand; the row must make sense without scrollback. Interviewed decisions do NOT appear here — they were resolved by the user and are briefed by the time of presentation.

Anti-pattern: bundling unilateral decisions deep in the Handoff section so they read as part of an approved plan. The reviewer must distinguish "user approved this" from "/planning:plan added this" without reading every line.
