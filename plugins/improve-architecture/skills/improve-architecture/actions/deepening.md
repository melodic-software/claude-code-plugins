# Deepening lens (Ousterhout)

The `deepening` action implements Ousterhout's "deepening" concept — finding shallow modules (interface nearly as complex as implementation) and proposing how to deepen them (small interface, large behavior behind it).

Three phases. Each has a hard gate before the next.

## Phase 1 — Explore for friction

Read the project's domain glossary if it maintains one — the nearest `UBIQUITOUS-LANGUAGE.md` (or equivalent), found by walking UP from the directory being examined toward the repo root and stopping at the first match (the same way `.editorconfig` / `.gitignore` resolve). Also read any architecture decision records in the area being examined.

Use the Agent tool with `subagent_type=Explore` (or any read-only exploration subagent available) to walk the codebase. Explore organically — note where friction appears:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as implementation?
- Where have pure functions been extracted for testability, but real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their **seams**?
- Where do bugs recur *at the seams between* several owned subsystems (e.g. frontend ↔ API ↔ CLI ↔ store) rather than inside any one — a signal to wrap them behind a single **deep** interface so one integration test exercises the whole flow instead of debugging each boundary?
- Which parts of the codebase are untested, or hard to test through their current **interface**?

Apply the **deletion test** to anything suspected shallow: would deleting it concentrate complexity, or move it? "Concentrates" is the signal. Full vocabulary in [../research/deepening/vocabulary.md](../research/deepening/vocabulary.md).

Classify each candidate's dependencies per [../research/deepening/dependencies.md](../research/deepening/dependencies.md) — the category determines testing strategy.

## Phase 2 — Present candidates as HTML report

Write a self-contained HTML file to the OS temp directory. Resolve temp dir from `$TMPDIR` / `$TEMP` / `/tmp`. Filename: `<tmpdir>/deepening-review-<timestamp>.html`. Open for user: `start <path>` on Windows, `open <path>` on macOS, `xdg-open <path>` on Linux. Report the absolute path.

Report is **self-contained — inline `<style>` + inline SVG only, no CDN or remote runtime** (a report that fetches remote assets is both a privacy and a supply-chain hazard, and breaks when opened offline). Build layout from an inline `<style>` block; draw diagrams as inline SVG or hand-built HTML/CSS — inline SVG node-and-edge for graph-shaped relationships, hand-built divs for editorial visuals (mass diagrams, cross-sections).

Each candidate gets a card with: files involved, problem (one sentence), solution (one sentence), before/after diagram, benefits in terms of **leverage** and **locality**, recommendation badge (`Strong` / `Worth exploring` / `Speculative`), dependency category badge.

End with a **Top recommendation** section. Full scaffold and diagram patterns in [../research/deepening/html-report.md](../research/deepening/html-report.md).

Use the project's domain glossary vocabulary for the domain, and [../research/deepening/vocabulary.md](../research/deepening/vocabulary.md) vocabulary for architecture.

**Durable candidate artifact.** Alongside the HTML (the human-readable companion, ephemeral in the temp dir), write a machine-readable candidate list that survives the session. Default location: `${CLAUDE_PLUGIN_DATA}/deepening-candidates-<timestamp>.md`. If the consuming project maintains its own per-task work-artifact convention (e.g. a tracked slice/working directory documented in its `CLAUDE.md` or rules), honor that instead and write the file there. Tell the user the path. This file — not the HTML — is the durable handoff a planning step consumes. One entry per candidate:

```markdown
## <candidate title>

- status: proposed | selected | agreed-shape | rejected
- files: <comma-separated paths>
- dependency-category: in-process | local-substitutable | ports-and-adapters | mock
- recommendation: Strong | Worth exploring | Speculative
- problem: <one sentence>
- deepening: <one sentence — the proposed deep interface>
- agreed-shape: <empty until Phase 3 — filled when the user picks and the shape is grilled: interface entry points, what sits behind the seam, tests that survive>
- rejected-reason: <only if status is rejected and the reason is load-bearing>
```

End the file with `top-recommendation: <candidate title>`.

**ADR conflicts**: if a candidate contradicts an existing architecture decision record, surface only when friction is real enough to warrant revisiting. Mark clearly in the card.

Do NOT propose interfaces yet. After the report is written, ask: "Which of these would you like to explore?"

## Phase 3 — Interview loop on selected candidate

Once the user picks a candidate, walk the design tree: constraints, dependencies, shape of the deepened module, what sits behind the seam, what tests survive.

Side effects inline as decisions crystallize:

- **New concept not in the project glossary?** If the project maintains a ubiquitous-language glossary, add the term immediately rather than batching it to the end.
- **Sharpening a fuzzy term?** Update the glossary right there.
- **User rejects a candidate with a load-bearing reason?** Offer to record it as an architecture decision — only when the reason would help a future explorer avoid re-suggesting it.
- **Want to explore alternative interfaces?** See [../research/deepening/interface-design.md](../research/deepening/interface-design.md) — "Design It Twice" via parallel subagents.

When the candidate's shape is agreed, update its entry in the candidate artifact to `status: agreed-shape` and fill `agreed-shape` (interface entry points, what sits behind the seam, tests that survive). Hand off to a planning step, which consumes the `agreed-shape` entry to plan the implementation. If no dedicated planning tool is available in the project, summarize the agreed shape directly so implementation can proceed.
