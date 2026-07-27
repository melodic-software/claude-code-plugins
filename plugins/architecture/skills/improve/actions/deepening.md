# Deepening lens (Ousterhout)

The `deepening` action implements Ousterhout's "deepening" concept — finding shallow modules (interface nearly as complex as implementation) and proposing how to deepen them (small interface, large behavior behind it).

Three phases, with a verification gate (Phase 1.5) between the scan and the report. Each has a hard gate before the next.

## Phase 1 — Explore for friction

Read the project's domain glossary if it maintains one — the nearest `UBIQUITOUS-LANGUAGE.md` (or equivalent), found by walking UP from the directory being examined toward the repo root and stopping at the first match (the same way `.editorconfig` / `.gitignore` resolve).

Also read any architecture decision records (ADRs) in the area being examined — give them the same discovery discipline as the glossary rather than one shallow glob. If the consuming project declares where its decisions live (a path in its `CLAUDE.md` / rules, or a documented convention), honor that. Otherwise walk a short ladder of the common homes, from the examined directory up to the repo root: `docs/adr/`, `docs/decisions/`, `doc/adr/`, `.adr/`, `adr/`, plus any `*.md` whose name matches `adr-*` / `*-decision*`. ADR placement varies widely; a single default glob misses most of them.

Use the Agent tool with `subagent_type=Explore` (or any read-only exploration subagent available) to walk the codebase. Brief each scan subagent with the canonical template in [../research/deepening/scan-briefing.md](../research/deepening/scan-briefing.md) — vocabulary primer, friction checklist, dependency categories, the two badge-acceptance heuristics, and the per-candidate return schema — so scan quality does not vary run-to-run and confidence is calibrated against the heuristics at scan time (not left to Phase 2). Explore organically — note where friction appears:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as implementation?
- Where have pure functions been extracted for testability, but real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their **seams**?
- Where do bugs recur *at the seams between* several owned subsystems (e.g. frontend ↔ API ↔ CLI ↔ store) rather than inside any one — a signal to wrap them behind a single **deep** interface so one integration test exercises the whole flow instead of debugging each boundary?
- Which parts of the codebase are untested, or hard to test through their current **interface**?

Apply the **deletion test** to anything suspected shallow: would deleting it concentrate complexity, or move it? "Concentrates" is the signal. Full vocabulary in [../research/deepening/vocabulary.md](../research/deepening/vocabulary.md).

Classify each candidate's dependencies per [../research/deepening/dependencies.md](../research/deepening/dependencies.md) — the category determines testing strategy.

## Phase 1.5 — Verify before publishing

Hard gate between the scan and the report. Scan-agent accuracy is mixed, and the HTML report is a user-facing artifact that lends every claim its authority — an overstated claim there is cheap to make and expensive to reputation. The scan output carries a `confidence` field (`strong` / `worth-exploring` / `speculative`) but no badge yet — the `recommendation` badge is assigned in Phase 2. Gate on the scan field that exists here. Before rendering Phase 2, adversarially verify:

- **Every candidate the scan returned with `confidence: strong`** (the ones headed for a `Strong` badge) — reproduce its `shallow-signal` (the concrete observation from the scan-briefing return schema). If the signal does not reproduce, drop the candidate's confidence below `strong`.
- **Every `runtime-claim`** — any candidate asserting a live bug or dead code. These are grep-cheap to check and the most damaging to get wrong (the worked failure: a scan reporting a service "registered but never composed" that a single grep showed *is* consumed, via a different consumer, with tests). Reproduce the claim against the actual code before it reaches the report; correct or drop it if it does not hold.

Verification can be a second cheap read-only subagent pass or inline reproduction — the bar is that no `confidence: strong` candidate and no runtime-bug/dead-code claim reaches Phase 2 unreproduced. Record what changed (downgraded, dropped, corrected) so the candidate artifact reflects the verified state, not the raw scan.

## Phase 2 — Present candidates as HTML report

**Re-badge first.** Before rendering, map each surviving candidate's scan `confidence` to its `recommendation` badge (`strong` → `Strong`, `worth-exploring` → `Worth exploring`, `speculative` → `Speculative`), then re-badge against the two acceptance heuristics below (deletion-test acceptance form, two-adapter rule) and the Phase 1.5 verification result — scan-time confidence is an input, not the final badge. A candidate whose `shallow-signal` failed to reproduce, or whose value rests on a one-adapter abstraction, cannot carry `Strong`. **Promotion closes the same gate:** if re-badging lifts a candidate the scan rated below `strong` up to `Strong`, apply the Phase 1.5 reproduction to its `shallow-signal` *before* it carries the badge — a `Strong` claim reaches the report reproduced no matter which way the badge was reached, so the Phase 1.5 guarantee holds across both the original strong set and any promotions.

Write a self-contained HTML file to the topic-docs **ephemeral tier** (see [../../../reference/topic-docs.md](../../../reference/topic-docs.md)): one file per run, via a secure temp-file primitive so the path is unpredictable and permissions are restrictive. On Unix/Linux, create it with `mktemp` (e.g. `mktemp --tmpdir deepening-review-XXXXXX.html` or `mktemp -t deepening-review.XXXXXX.html`); on Windows, use a user-scoped temp under `%LOCALAPPDATA%\Temp` or equivalent. Resolve that one path deterministically — never branch on an injected scratchpad path or `CLAUDE_JOB_DIR`. Open for user: `start <path>` on Windows, `open <path>` on macOS, `xdg-open <path>` on Linux. Report the absolute path. Do **not** delete the file after reporting: the path is the delivery mechanism and must stay readable for the user to open. It outlives the invocation and nothing documented reclaims the OS temp tree on a schedule, which is why one run writes one file and never an accumulating tree.

Report is **self-contained — inline `<style>` + inline SVG only, no CDN or remote runtime** (a report that fetches remote assets is both a privacy and a supply-chain hazard, and breaks when opened offline). Build layout from an inline `<style>` block; draw diagrams as inline SVG or hand-built HTML/CSS — inline SVG node-and-edge for graph-shaped relationships, hand-built divs for editorial visuals (mass diagrams, cross-sections).

Each candidate gets a card with: files involved, problem (one sentence), solution (one sentence), before/after diagram, benefits in terms of **leverage** and **locality**, recommendation badge (`Strong` / `Worth exploring` / `Speculative`), dependency category badge.

Two acceptance heuristics gate the badge:

- **Deletion test (acceptance form)** — would a future maintainer, finding this module gone, rebuild it substantially the same way? If not, the module boundary is arbitrary and the candidate is weak.
- **Two-adapter rule** — an abstraction or port earns its existence only with two real consumers/adapters (typically production + test). A candidate whose value hinges on a one-adapter abstraction is speculative indirection — badge it `Speculative` at best.

End with a **Top recommendation** section. Full scaffold and diagram patterns in [../research/deepening/html-report.md](../research/deepening/html-report.md).

Use the project's domain glossary vocabulary for the domain, and [../research/deepening/vocabulary.md](../research/deepening/vocabulary.md) vocabulary for architecture.

**Durable candidate artifact.** Alongside the HTML (the human-readable companion, ephemeral in the temp dir), write a machine-readable candidate list that survives the session. Resolve its location through the marketplace topic-docs convention per this plugin's binding ([../../../reference/topic-docs.md](../../../reference/topic-docs.md)): the **memory tier** — `<memory_dir>/<topic-slug>/deepening-candidates-<YYYYMMDDTHHMMSSZ>.md`, default `.work/<topic-slug>/…`. The convention's resolution order governs (the consuming repo's `.claude/topic-docs.yaml`, then its own declared working-docs convention, then the documented defaults), as do its slug spec and the memory root's self-ignore guard; create the topic slice directory when absent. Tell the user the path. This file — not the HTML — is the durable handoff a planning step consumes. One entry per candidate:

```markdown
## <candidate title>

- status: proposed | selected | agreed-shape | rejected
- files: <comma-separated paths>
- dependency-category: in-process | local-substitutable | ports-and-adapters | mock
- recommendation: Strong | Worth exploring | Speculative
- problem: <one sentence>
- deepening: <one sentence, narrative — the shallow-module friction, not an interface proposal; e.g. "three modules wrap a single call each, adding no behavior">
- shallow-signal: <the concrete observation — evidence, not narrative; e.g. "OrderHandler/OrderValidator/OrderRepo each forward their one argument unmodified (confirmed by reading all three)". Reproduced in Phase 1.5 for every `Strong` candidate; a runtime-claim candidate has its *claim* reproduced, not this signal, so unless it is also `Strong` the signal here is the scan's as-reported observation, not yet reproduced>
- signal-verified: <true only once Phase 1.5 reproduced *this signal* — i.e. every `Strong` candidate. A runtime-claim reproduction verifies the claim, not the shallow-signal, so a runtime-claim candidate left below `Strong` keeps `signal-verified: false`. This keeps the planning handoff from ever reading an unverified shallowness observation as verified>
- agreed-shape: <empty until Phase 3 — filled when the user picks and the shape is grilled: interface entry points, what sits behind the seam, tests that survive>
- rejected-reason: <only if status is rejected and the reason is load-bearing>
```

End the file with `top-recommendation: <candidate title>`.

**ADR conflicts**: if a candidate contradicts an existing architecture decision record, surface only when friction is real enough to warrant revisiting. Mark clearly in the card.

Do NOT propose interfaces yet. After the report is written, ask: "Which of these would you like to explore?"

## Phase 3 — Interview loop on selected candidate

Once the user picks a candidate, walk the decision tree: constraints, dependencies, shape of the deepened module, what sits behind the seam, what tests survive.

Side effects inline as decisions crystallize:

- **New concept or sharpened term?** Invoke `/domain-driven-design:curate-language` immediately
  when that skill is available in the current session; it owns active glossary maintenance and
  known-context routing.
  Otherwise preserve the existing fallback: update a consumer-declared ubiquitous-language glossary
  in its own shape. If no convention exists, offer discovery-first lazy creation without prescribing
  a filename.
- **User rejects a candidate with a load-bearing reason?** Offer to record it as an architecture decision — only when the reason would help a future explorer avoid re-suggesting it.
- **Naming an exemplar call site to anchor the shape?** Read it before locking the shape around it. An exemplar chosen from memory or a candidate's file list can turn out not to fit once actually read; validate the fit first, and if it does not hold, search for a call site that does rather than shaping the interface around the wrong one.

### Design-It-Twice exploration mode

Branch here when the user wants alternative interfaces for the selected candidate, or a single proposed shape isn't converging. Grounded in Ousterhout's design-it-twice principle — the first workable design is rarely the deepest. Frame the problem space and show it to the user, fan out 3–4 parallel subagents each under a deliberately orthogonal design constraint, present the returned designs sequentially, compare on interface depth/leverage, locality of change, and seam placement, then close with an opinionated recommendation (hybrid allowed). Full process: [../research/deepening/interface-design.md](../research/deepening/interface-design.md). Feed the winning shape back into the interview loop — it becomes the `agreed-shape` once grilled.

### Handoff

When the candidate's shape is agreed, update its entry in the candidate artifact to `status: agreed-shape` and fill `agreed-shape` (interface entry points, what sits behind the seam, tests that survive). Hand off to a planning step, which consumes the `agreed-shape` entry to plan the implementation. If no dedicated planning tool is available in the project, summarize the agreed shape directly so implementation can proceed.
