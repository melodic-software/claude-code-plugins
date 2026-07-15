# Interface Design — Design It Twice

Full process for the Design-It-Twice exploration mode of the deepening interview loop. Grounded in Ousterhout's design-it-twice principle: the first workable design is rarely the deepest, and producing several radically different alternatives costs little next to living with a shallow interface for years.

## 1. Frame the problem space

Before any design work, write a user-facing framing of the problem space for the selected candidate:

- The constraints any new interface must satisfy — existing callers, invariants that must hold, ordering and performance facts callers already rely on
- The candidate's dependencies and their categories per [dependencies.md](dependencies.md)
- A small illustrative code sketch that makes the constraints concrete — labeled explicitly as **not a proposal**; it exists so the constraints stop being abstract, nothing more

Show the framing to the user, then move straight to step 2. The user absorbs the framing while the subagents work.

## 2. Fan out to parallel subagents

Spawn 3–4 subagents in parallel via the Agent tool. Orthogonality is deliberate — each subagent gets one design constraint chosen so the resulting interfaces cannot converge on the same shape:

- **Minimal interface** — 1–3 entry points at most; squeeze maximum leverage from each
- **Maximum flexibility** — support many use cases and extension
- **Optimize the common caller** — the dominant call site's default case becomes trivial
- **Ports and adapters** (only when the candidate's dependency classification shows cross-seam dependencies) — port at the seam, transport injected

Brief each subagent with the concrete technical context — file paths, coupling details, dependency category, what sits behind the seam — independent of the user-facing framing from step 1. Include [vocabulary.md](vocabulary.md) terms and the project's own glossary terms (if it maintains one) so every design names things consistently.

Every subagent returns the same five-part structure:

1. **Interface** — types, methods, params, plus the rest of what a caller must know: invariants, ordering constraints, error modes
2. **Usage example** — real caller code against the proposed interface
3. **What the implementation hides** — the complexity absorbed behind the seam
4. **Dependency strategy** — how each dependency is handled and which adapters exist
5. **Trade-offs** — where the design's leverage is high, and where it thins out

## 3. Present and compare

Present the designs one at a time so the user can absorb each before the next arrives. Then compare across three axes:

- **Interface depth / leverage** — behavior per unit of interface a caller must learn
- **Locality of change** — where future change, bugs, and verification concentrate
- **Seam placement** — where each design puts the seam, and what that position costs or buys

## 4. Recommend

Close with your own read: which design wins, and why. If pieces of different designs combine into something stronger, propose the hybrid explicitly. Be opinionated — the user is here for a strong recommendation, not a menu of equally weighted options.
