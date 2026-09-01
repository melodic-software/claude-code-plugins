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
- [Plan](#plan)
- [Blast radius](#blast-radius)
- [Stress-test summary](#stress-test-summary)
- [Execution shape](#execution-shape)
- [Open questions](#open-questions)
- [Handoff to implementation](#handoff-to-implementation)

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

## Plan

Session directive: all wave-1 work executes in this session, on this branch, closing in one
PR; deferred and gated work is filed as issues carrying its context. The session's working
memory is container-ephemeral, and the contract slice itself is branch-lived (the prune
gate red-lines any new `docs/topics/` slice in a PR), so durable context is routed into
surfaces that survive merge: the doctrine doc, the issue bodies, and the PR body carrying
this plan at close-out.

### Standards grounding

Standards resolved at the inference rung (no `.claude/standards.yaml`, no `docs/standards/`
index; no personal overlays found). Sections loaded for the touched surfaces:
`docs/conventions/config-cascade/README.md` (layer order, ratified inversion class, concern
declaration duties, the Implementers conformance table), `docs/conventions/topic-docs/README.md`
(tiers, the contract-slice lifecycle and prune gate), `docs/conventions/untrusted-content/README.md`
(read-trust vs containment), `docs/PLUGIN-PHILOSOPHY.md` (userConfig scope, native-mechanism
preference, no cross-plugin path citations), the affected-tests contract (`README.md`
"Validate a change" plus `scripts/affected-tests-no-suite.txt`), and
`scripts/cross-plugin-source-registry.txt` plus its drift checker (a registered path in
fewer than two plugins fails as REGISTRY STALE). Hook budget and catalog taxonomy are
untouched by this wave.

### Phase 1: Chrome and token reference asset plus validation lane [TODO]

Author `plugins/visualization/reference/html-chrome.html`: a self-contained reference page
carrying the corpus design-token system (ivory/slate/clay/oat/olive palette, serif/sans/mono
stacks, border and radius scale) and the provisional accessibility floor (contrast pairings,
focus states, `prefers-color-scheme` and `prefers-reduced-motion` behavior), with a header
comment naming its source and license provenance (template repo MIT; live gallery pages
Apache-2.0) and marking the floor provisional per the Brief's carry-forward. No registry row
this wave: the drift checker fails a registered path carried by fewer than two plugins, so
the doctrine doc records the standing instruction that the second adopter registers the
cluster (path-within-plugin spelling: `reference/html-chrome.html`). The validation lane is
a real shell suite in the same commit: pin `htmlhint` at an exact version in `package.json`
devDependencies (lockfile updated via the repo's npm tooling), add
`scripts/check-html-assets.sh` invoking `node_modules/.bin/htmlhint` over tracked
`plugins/*/reference/*.html`, give it the repo-standard `.test.sh` twin, and wire the
mapping so `affected-tests` selects it for the asset class; whether that wiring is a mapping
edit or also a `ci.yml` job is read off the affected-tests contract at execution time, and
the ci edit is in scope if the contract demands a named lane.

**Sanity Check:** `node_modules/.bin/htmlhint` over the asset exits 0;
`scripts/check-html-assets.test.sh` exits 0; `scripts/affected-tests.sh --explain` on the
asset selects the new suite; `scripts/check-cross-plugin-source-drift.sh --check` exits 0
(no registry row added); `scripts/affected-tests.sh --run` exits 0.

### Phase 2: Doctrine doc plus cascade concern registration [TODO]

Write `docs/conventions/rendered-views/README.md`, the single owner doc, carrying: the
boundary rule (Brief decision 2) with the reachability-and-preference matrix; both
reconciliation sentences (decisions 4 and 5, including the native Artifact switches as the
day-one flip); the genre rubric with its stopping rule and the per-skill instruction-size
budget; the corpus distillate future verticals need (genre taxonomy and the nine
cross-cutting pattern families, since this doc is where they become house doctrine); the
enumerated wave-1 adoption list; the retrofit list for existing lanes that render
untrusted-ish content; the security-baseline skeleton, stated honestly as
instruction-level discipline (markup linting validates syntax, not escaping; the
deterministic helper is required before any attacker-controlled lane); the accessibility
flip-back clause; the registry-intent note from phase 1; and the `rendered-views` cascade
concern declaration with the concrete surface path all three layers resolve
(`.claude/rendered-views.md`, per the cascade contract's concern-file rules), its keys,
per-key override statements, the tier ladder `argument > plugin dial > cascade > shipped
default`, and the resolution liturgy. Add the concern's row to the Implementers table in
`docs/conventions/config-cascade/README.md` in the same commit, as that contract requires.

**Sanity Check:** greps find the tier-ladder line, both reconciliation sentences, the
retrofit-list heading, and the pattern-families heading in the new README; grep finds the
`rendered-views` row in the config-cascade Implementers table;
`scripts/affected-tests.sh --run` exits 0.

### Phase 3: userConfig probe gate [TODO]

Before any wiring: attempt a non-interactive probe of `${user_config.*}` substitution
behavior on the installed CLI (inspection of the substitution path without the interactive
`/plugin` dialog) and record the outcome in this file. The Brief's acceptance criterion 6
requires the smoke test before seam wiring lands; this environment may block the
interactive flow, so the approval gate below carries the owner's ruling: on a blocked
probe, criterion 6 is amended so the recorded probe outcome plus a filed gating issue
(issue 2, gating the fleet sweep) satisfies it for this wave, because the wave introduces
no new dial. Absent that amendment, a blocked probe halts phase 4.

**Sanity Check:** a `Probe outcome (2026-09-01):` line exists in this section with a
recorded result; the amendment status is stated on the same line.

### Phase 4: Seam exemplar wiring [TODO]

Wire the cascade rung into `visualization:visualize`: the `medium` resolution becomes
`argument > ${user_config.medium} > rendered-views cascade > auto`, with provenance
reported and a visible degrade when a layer is absent. The SKILL.md carries the resolution
inline with a provenance citation of the owning convention (the pattern its existing
topic-docs citation already uses), never a bare repo path an installed consumer cannot
resolve; the wiring stays within a 30-line SKILL.md delta. Add an eval row exercising
cascade resolution and the visible degrade, alongside whatever version bookkeeping the
validators demand (plugin semver bump, changelog entry, options-doc regeneration).

**Sanity Check:** grep finds the four-rung ladder in the visualize SKILL.md;
`git diff --numstat` for the SKILL.md shows at most 30 added lines; grep finds the new
cascade eval in the visualize evals file; `scripts/affected-tests.sh --run` exits 0
(skill-quality, options-docs sync, and changelog parity gates included).

### Phase 5: Deferred-work issues [TODO]

File seven issues, each carrying its distilled context inline (the 31-demo inventory
slices, talking points, and license split ride the issues that need them, since the topic
slice does not survive merge): fleet ladder sweep and evals reconciliation; userConfig
live smoke test (gates the sweep); deterministic escape helper plus the review-plugin PR
explainer (wave 2, gated); reports and research genre lanes; loop-closure and export
pattern snippets; template vendoring decision; retrofit execution for the doctrine's
retrofit list. Search before creating; check issue types first; record the search outcome.
Then replace this phase's body with a `#### Deferred-work issues` list holding exactly the
seven URLs.

**Sanity Check:** `grep -c 'github.com/melodic-software/claude-code-plugins/issues/'` on
this file returns exactly 7; the pre-creation search outcome is recorded in this section.

### Phase 6: Close-out and PR [TODO]

Run the contract-slice close-out (per the planning close-out procedure): paste this PLAN
into the PR body, graduate durable outcomes (the doctrine doc already lives in
`docs/conventions/`; apply the ADR admission test to the adoption ruling and write the ADR
only if it passes), delete `docs/topics/html-effectiveness-discussion/` in the final
commit, and open the single PR for this branch with the repo's PR conventions.

**Sanity Check:** `scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0;
`scripts/affected-tests.sh --run` exits 0 on the final tree; the PR exists and its body
carries the plan.

## Blast radius

MEDIUM. The wave adds a new CI-checked asset class and validation suite, two convention
surfaces, and one plugin's instruction change; no runtime code paths change, and existing
surfaces keep their shipped behavior by explicit decision. Cross-plugin and CI touchpoints
are what lift it above LOW.

## Stress-test summary

The package-level `/planning:devils-advocate` ran before this plan was drafted (one CRITICAL
resolved by owner ruling on precedence; three HIGH folded into the Brief's decisions 5, 6,
and 7). The plan-level stress-test ran as the mandatory fresh-context plan review with the
devils-advocate lens folded into its brief (a third full devils-advocate over the same
substance was judged redundant; surfaced for the approver). That review returned 3 CRITICAL
/ 5 IMPORTANT / 4 SUGGESTION findings; all twelve were verified against the actual files
and folded into the phases above: no registry row this wave, a real close-out prune phase,
durable context re-routed off the contract tier, a real validation suite instead of a
no-suite claim, the Implementers-table duty, the probe gate resequenced ahead of wiring
with an explicit amendment ask, self-matching and non-mechanical sanity checks repaired,
an eval for the cascade rung, the honest instruction-level security wording, the
inline-carry citation form, and the exact-pin lint invocation.

## Execution shape

Fully sequential, all main-session: each phase consumes the previous phase's outputs (the
doctrine cites the asset, the exemplar cites the doctrine, the issues cite all three), the
work is judgment-heavy prose and configuration rather than parallel-safe volume, and one
writer avoids scope-fence risk on a single branch. One commit per phase.

## Open questions

Two Brief-amendment items ride the approval. Criterion 6 (phase 3): on a blocked probe, the
recorded outcome plus the gating issue satisfies it for this wave. Criterion 2 (phase 1):
"registry-synced copies with a passing drift check" is satisfied this wave by the single
canonical copy plus the doctrine's second-adopter registration rule, because the drift
checker mechanically rejects a one-plugin registration. Everything else in the plan traces
to the Brief or a verified reviewer finding.

## Handoff to implementation

### User-approval gates

The plan approval itself; the phase 3 criterion 6 amendment and the phase 1 criterion 2
amendment, both `[FALLBACK — confirm or override]`; any mid-flight pivot that changes an
acceptance criterion.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential single-session execution; phase order fixed by the Brief's landing order with
the probe gate inserted before wiring; doctrine doc named `rendered-views`; cascade concern
named `rendered-views` with surface path `.claude/rendered-views.md`; `htmlhint`
exact-pinned with a `check-html-assets` suite as the validation lane;
`visualization:visualize` as the wave-1 exemplar with a 30-line wiring budget; seven issues
as the deferred-work split; registry registration deferred to the second adopter by
mechanical necessity.

### Mechanical work

One commit per phase riding that phase's changes plus its PLAN.md tag update; validation
via `scripts/affected-tests.sh --run` at every phase boundary; sequential fallback is the
shape itself (no parallel path to fall back from); the PR at phase 6 is the single
publication event, with the slice pruned and the plan preserved in the PR body.
