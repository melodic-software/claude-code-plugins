# The unreasonable effectiveness of HTML: marketplace integration

## Contents

- [Brief](#brief)
  - [TLDR](#tldr)
  - [Provenance](#provenance)
  - [Goal](#goal)
  - [Settled decisions](#settled-decisions)
  - [Constraints](#constraints)
  - [Rollout shape](#rollout-shape)
  - [Acceptance criteria](#acceptance-criteria)
  - [Named assumptions](#named-assumptions)
  - [Carry-forward items](#carry-forward-items)
- [Handoff](#handoff)

## Brief

Status: **Brief locked** 2026-09-01. Every register question answered and signed off by the
owner after an adversarial validation chain (blindspot scan, brainstorm, devils-advocate,
two-validator answer audit). Planning for wave 1 is the next stage.

### TLDR

Adopt the "Unreasonable Effectiveness of HTML" doctrine the way the source actually argues it:
person-facing deliverables in its genres default to self-contained local HTML views, while
markdown stays the record and the pipeline format. Ship it as codification of the house rules
this repo already practices, carried by one owner convention doc, a registry-synced design-token
and chrome reference, a config-cascade preference seam, and a staged escaping baseline, with the
review-plugin PR explainer as the flagship second wave.

### Provenance

Source corpus: the X article "Using Claude Code: The Unreasonable Effectiveness of HTML"
(Thariq Shihipar, 2026-05-08), its claude.com blog republication, the 20-demo example gallery
plus the 11-page "Know your unknowns" collection, the anthropics/html-effectiveness template
repo, and the linked playgrounds post. The whole corpus was snapshot, inventoried, digested,
and dual-verified in-session; coverage against the three original sources graded FULL. Official
mechanisms (userConfig, settings precedence, the Artifacts account model) were re-verified
against live docs current as of Claude Code v2.1.252.

### Goal

Align the marketplace with the corpus doctrine so that skills whose deliverable a person reads
produce a rich, self-contained HTML view by default where that makes sense, every default is
user-overridable through official seams, and nothing weakens the repo's record-vs-view,
validation, or security contracts.

### Settled decisions

1. **Adoption stance.** Lean into the research. HTML lanes are decided per skill by genre
   (exploration grids, plans, review explainers, reports, research explainers, decks, custom
   editors, unknowns-lifecycle artifacts). The repo ships an opinionated default; users
   override it. Binding lens: plugins stay user-configurable, extensible, and repo-, machine-,
   and company-agnostic.
2. **Boundary rule** (one owner convention doc). Pipeline and agent-read artifacts are always
   markdown. Person-facing corpus-genre deliverables default to a self-contained local HTML
   view only where the next consumer is a person and the environment can serve a viewable
   file. Dual-audience reports, whose next consumer is often another agent pass, offer the
   view instead of emitting it by default. Reachability constrains, preference selects within
   reachable rungs, and degrades are visible with provenance. Accessibility is a named,
   sanctioned reason to prefer markdown.
3. **Anti-"/html skill" form.** Per-skill genre ownership of page shapes. The one sanctioned
   shared piece is a design-token and chrome reference carrying the accessibility floor,
   shipped as registry-synced per-plugin copies through the cross-plugin source registry (a
   single cited file cannot reach installed consumers). No generic HTML-generating skill;
   `visualization:visualize` stays a router that owns no craft.
4. **Residence.** Local-first: machine-local HTML files are the primary lane for new work and
   for the owner's own environment; deliverables are untracked by default; publishing anywhere
   stays optional and configurable, never the default.
5. **Default ladder.** Artifact-first remains the shipped default for the existing emitting
   surfaces (their evals enforce it). The doctrine names the native Artifact disable switches
   (`enableArtifact: false`, `CLAUDE_CODE_DISABLE_ARTIFACT=1`, a `permissions.deny` Artifact
   rule) as the day-one per-user flip. The reconciliation is explicit: decision 4 governs new
   lanes and personal environments via the native flip; this decision grandfathers existing
   surfaces until the priced release sweep. The preference seam covers only what natives
   cannot express (terminal-vs-file choice, genre dials, team policy).
6. **Preference precedence** (hybrid). The cross-plugin output-format concern rides the
   config-cascade convention: the repo layer refines the user-global layer per the ratified
   base law, and the local overlay is the user's per-repo trump. Per-plugin `userConfig`
   carries only plugin-specific dials under distinct keys. Tier ladder: explicit argument,
   then plugin dial, then cascade resolution, then shipped default. The doctrine states
   plainly that the user's global preference governs wherever no repo layer speaks.
7. **Escaping baseline** (staged). Wave 1 ships an instruction baseline plus linter heuristics
   as the skeleton for existing low-adversarial lanes. A checked-in deterministic escape
   helper (a new registry sync cluster, with a generator-marker tell a validator can check) is
   required before any lane that renders attacker-controlled input, the review explainer first
   among them.
8. **Artifacts posture.** Cross-account artifact sharing and editing is treated as unavailable
   everywhere in the plan; a re-check trigger is recorded against future version bumps.
9. **Verification debt.** One live `userConfig` smoke test on the current CLI runs before the
   multi-surface seam wiring relies on any dial.

### Constraints

- The record-vs-view rule is inviolable: nothing downstream ever re-reads an HTML view, and no
  view sits beside the record it renders.
- Any checked-in HTML/CSS asset lands with a named, pinned validation lane mapped in the
  affected-tests contract in the same PR; a zero-suite file is an error here.
- The accessibility floor (contrast, focus states, color-scheme and reduced-motion behavior)
  lives in the shared reference and is decided as a cross-cutting concern, never anchored to
  one genre's needs.
- Per-skill instruction cost is budgeted: the HTML lane and the cascade read liturgy count
  against an explicit size budget per adopting skill.
- Registry-synced copies keep an identical path within every adopting plugin, and the asset
  counts against each plugin's shipped size.

### Rollout shape

- **Wave 1**: the design-token and chrome reference plus its validation lane (same PR), and
  the owner doctrine doc carrying the boundary rule, the reconciliation sentences, the genre
  rubric with its stopping rule, the enumerated wave-1 adoption list, the per-skill size
  budget, and the security-baseline skeleton. The preference seam and the escaping mechanism
  follow within the wave now that both are ruled; the smoke test precedes seam wiring. An
  explicit retrofit list covers existing lanes that render untrusted-ish content.
- **Wave 2**: the review-plugin HTML PR explainer, gated on the deterministic escape helper.
- **Deferred**: reports/research genre lanes, loop-closure and export pattern snippets, and
  any vendoring of the corpus templates (license provenance recorded: the template repo is
  MIT while the live gallery pages carry Apache-2.0 headers; vendoring must name its source).

### Acceptance criteria

1. The owner convention doc exists, states decisions 2, 5, and 6 verbatim in substance
   (including both reconciliation sentences and the reachability rung), and is the single
   home other surfaces point to.
2. The shared reference ships as registry-synced copies with a passing drift check and a
   validation lane the affected-tests contract maps; no consumer-facing skill cites a
   repo-only path.
3. The preference resolves per the tier ladder in at least one adopting skill end to end,
   with provenance reported and a visible degrade when a layer is absent.
4. The escaping skeleton is ratified before any new HTML lane ships; the review explainer
   does not ship without the deterministic helper and its verifiable tell.
5. Existing emitting surfaces keep passing their current evals until the priced sweep
   deliberately changes them.
6. The userConfig smoke test has run and its outcome is recorded before seam wiring lands.

### Named assumptions

- The official `userConfig` mechanism behaves as documented on the current CLI (checked by
  the smoke test rather than trusted).
- The absence findings hold until a version bump: no marketplace-level userConfig, and no
  cross-account artifact bridge or roadmap. Both were verified against live docs and both
  carry re-check triggers.
- The corpus's cost claims (more tokens, slower generation, noisy diffs) are accepted as
  stated by its author and are managed by the offer-not-emit rule and untracked residence
  rather than re-measured.

### Carry-forward items

- The remaining interview verticals (loop-closure mechanics, genre deep-dives, sourcing)
  run later and inherit the settled halves of this Brief; the design-system vertical decides
  the accessibility floor cross-genre when it fires.
- A wave-1 ordering sentence: the shared reference lands with, or after, the design-system
  vertical's floor decision if that vertical fires first; otherwise the reference carries a
  provisional floor the vertical may revise.

## Handoff

Next stage: `/planning:plan` over this Brief for wave 1. The plan owes the doctrine doc's
outline, the registry cluster and validation-lane mechanics, the enumerated adoption list, the
retrofit list, and the smoke-test procedure, in the landing order the rollout shape fixes.
