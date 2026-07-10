# Interface Design — "Design It Twice"

When the user wants to explore alternative interfaces for a chosen deepening candidate, use parallel subagents. Based on Ousterhout's "Design It Twice" — first idea is unlikely to be best.

## Process

### 1. Frame the problem space

Before spawning subagents, write a user-facing explanation:

- Constraints any new interface must satisfy
- Dependencies and their category (per [dependencies.md](dependencies.md))
- Rough illustrative code sketch grounding the constraints — not a proposal

Show to user, then immediately proceed to Step 2. User reads while subagents work.

### 2. Spawn parallel subagents

Spawn 3+ subagents via Agent tool. Each must produce a **radically different** interface for the deepened module.

Prompt each with a separate technical brief (file paths, coupling details, dependency category, what sits behind the seam). Give each a different design constraint:

- **Agent 1:** "Minimize the interface — 1-3 entry points max. Maximize leverage per entry point."
- **Agent 2:** "Maximize flexibility — support many use cases and extension."
- **Agent 3:** "Optimize for the most common caller — make the default case trivial."
- **Agent 4 (if applicable):** "Design around ports and adapters for cross-seam dependencies."

Include both [vocabulary.md](vocabulary.md) terms and the project's own glossary terms (if it maintains one) in the brief so subagents name things consistently.

Each subagent outputs:

1. Interface (types, methods, params — plus invariants, ordering, error modes)
2. Usage example showing how callers use it
3. What the implementation hides behind the seam
4. Dependency strategy and adapters
5. Trade-offs — where leverage is high, where it's thin

### 3. Present and compare

Present designs sequentially so user absorbs each, then compare in prose. Contrast by **depth** (leverage at interface), **locality** (where change concentrates), and **seam placement**.

Give your recommendation: which design is strongest and why. If elements from different designs combine well, propose a hybrid. Be opinionated — user wants a strong read, not a menu.
