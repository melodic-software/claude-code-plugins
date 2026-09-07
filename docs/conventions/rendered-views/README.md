# Rendered Views Convention

The marketplace-wide contract for person-facing rendered HTML views: when a skill's
deliverable defaults to a self-contained HTML page, when it stays markdown or terminal
output, how the choice is overridden, and what every rendered view owes for security and
accessibility. Adopted from the "Unreasonable Effectiveness of HTML" corpus (the article,
its example gallery, and the "Know your unknowns" collection) through a full interview,
stress-test, and validation chain; the decision record travels with the pull request that
introduced this document.

This directory is the source of truth for the concern. The shared chrome and token
reference lives in the adopting plugins (canonical copy:
`plugins/visualization/reference/html-chrome.html`).

## The boundary rule

**Markdown is the record. HTML is an optional rendered view of a record kept elsewhere.**

- Pipeline and agent-read artifacts (ledgers, checklists, handoffs, digests, findings a
  later pass consumes) are always markdown. Nothing downstream ever re-reads an HTML view,
  and no view may sit beside the record it renders.
- A deliverable in one of the corpus genres (see the rubric below) defaults to a
  self-contained local HTML view only when BOTH hold: the next consumer is a person, and
  the environment can serve a viewable file.
- A dual-audience report, one that another agent pass re-reads (audit findings feeding a
  fix pass, scan results feeding triage, quiz records feeding recall), OFFERS the view
  instead of emitting it by default. The markdown record is the deliverable; the view is
  an option.

## Reachability and preference

Reachability constrains; preference selects within reachable rungs; every degrade is
visible and names its cause.

| Environment | Reachable rungs |
|---|---|
| Local interactive session | published artifact, local file, terminal |
| Remote or web session | published artifact, a file sent to the user, terminal |
| CI or non-interactive run | terminal or the record only, no view emitted |

A skill that cannot serve its preferred rung says so and names the layer or environment
fact that decided the outcome, rather than silently printing a dead file path.

## Default ladder and its reconciliation

The shipped default ladder for existing emitting surfaces stays **published artifact,
then local file, then terminal**, exactly as those surfaces and their evals ship today.
Two sentences reconcile this with the local-first residence decision:

1. Local-first governs NEW rendered-view lanes and any operator's personal environment:
   the native Artifact disable switches (`enableArtifact: false` in settings, the
   `CLAUDE_CODE_DISABLE_ARTIFACT=1` environment variable, or a `permissions.deny`
   `Artifact` rule) are the sanctioned day-one flip that turns every ladder local, with
   zero plugin changes.
2. The existing emitting surfaces are grandfathered on the shipped ladder until the
   priced fleet sweep deliberately migrates them (tracked as a deferred-work issue).

Rendered views are untracked by default; publishing anywhere is optional and configured,
never the default.

Standing re-check trigger: cross-account and cross-subscription artifact sharing/editing
was verified absent with no documented roadmap (docs current at Claude Code v2.1.252).
That absence claim is re-checked against the upstream artifacts doc and changelog on
future version bumps before any plan relies on it staying true.

## Genre rubric and stopping rule

A skill's deliverable is in scope for an HTML-view lane only when it falls in one of the
corpus genres:

exploration grids and option spreads; plans presented for approval; code-review
explainers; reports, status, and post-mortems; research and concept explainers; decks;
custom throwaway editors; unknowns-lifecycle artifacts (blindspot passes, interviews,
comprehension quizzes).

The stopping rule: a lane is added per skill, by a change that names the genre the
deliverable belongs to and applies the dual-audience test above. A deliverable that fits
no genre gets no lane, and a genre argument is settled by this list, amended here first.
The instruction-size budget: an HTML-view lane (ladder, chrome citation, escaping note)
adds at most 40 lines to a SKILL.md; the cascade wiring adds at most 30. A lane that
cannot fit the budget is a design smell, not a reason to raise the budget silently.

## Corpus distillate

Retained here because the working session's corpus artifacts are ephemeral; this is the
distillate future adoption waves need.

Genre taxonomy (gallery): exploration and planning; code review and understanding;
design; prototyping; illustrations and diagrams; decks; research and learning; reports;
custom editing interfaces. Lifecycle taxonomy (unknowns collection): pre-implementation,
during, post-implementation.

The nine cross-cutting pattern families verified across all 31 corpus demos:

1. One design-token system corpus-wide (the palette and stacks the shared reference
   carries).
2. Absolute self-containment: zero external links, scripts, or images in every demo.
3. A loop-closure family with escalating payloads: numbered resonate tokens, chip-built
   replies, generated follow-up prompts, accept/correct sign-offs, live-state exports;
   absent by design in the writeup/report genre.
4. Identical clipboard boilerplate in every interactive page (shared-helper candidate,
   deferred with the loop-closure issue).
5. Prompt provenance split by genre: exploratory pages embed their generating prompt,
   reportive pages do not.
6. Badge and taxonomy vocabularies invented per page, never shared.
7. A JS-necessity spectrum from zero-script reports to simulation-grade editors.
8. Accessibility explicitly deferred in the corpus's prototypes (why this repo ships a
   floor instead).
9. The unknowns lifecycle maps one-to-one onto this marketplace's existing skill lanes.

Named costs the corpus itself records: more tokens, two to four times the generation
time, and noisy diffs under version control; the offer-not-emit rule and untracked
residence are how this convention prices them.

## Wave-1 adoption and grandfathered surfaces

Wave-1 adopter (cascade wiring plus chrome citation): `visualization:visualize`.

Current emitters, grandfathered on their shipped behavior: `adhd:clarify`,
`architecture:improve`, `education:quiz-me`, `education:teach`,
`prototype:explore-directions`, `prototype:pressure-test`, `machine-health:audit`,
`claude-ops:observability`, `planning:interview` (and planning's other rendered views),
`overengineering:audit`, `event-storming:simulation`, `ai-briefing:generate`,
`visualization:visualize`.

Retrofit list (existing lanes rendering untrusted-ish content, aligned to the security
baseline by the tracked retrofit issue, not silently): `adhd:clarify`,
`architecture:improve`. Both were retrofitted by #3609: each HTML lane repeats the
baseline's rules in its own instruction text (a skill runs where this file is not on
disk) and keeps only additions specific to that surface.

## Security baseline (wave-1 skeleton)

Instruction-level discipline, stated honestly: markup linting validates syntax, not
escaping, so this baseline is authoring discipline until the deterministic helper ships.

- Everything interpolated into a rendered view is untrusted DATA: escape `&`, `<`, `>`,
  `"`, and `'` in text and attribute positions; never interpolate unescaped content into
  `<script>` or `<style>`; never build event-handler attributes from input.
- Views are self-contained: no external requests, no remote scripts, assets inline.
- A lane that renders attacker-controlled input (a PR diff, fetched web content, another
  repo's files) MUST NOT ship on this skeleton alone: it is gated on the checked-in
  deterministic escape helper with a generator-marker a validator can check (tracked as
  the wave-2 issue; the review-plugin PR explainer is the first gated lane).

Checked-in `.html` assets are validated by `scripts/check-html-assets.sh` (registration
manifest plus pinned htmlhint), wired into CI.

## Accessibility floor

The floor (contrast pairings, focus visibility, color-scheme and reduced-motion behavior,
keyboard reach) lives in the shared chrome reference and is provisional until the
design-system vertical revisits it cross-genre. Accessibility is a named, sanctioned
reason to prefer markdown over a rendered view: when a reader's tooling or needs make the
markdown record the better deliverable, flipping back is conformant, not a deviation.

## The shared chrome reference

Canonical copy: `plugins/visualization/reference/html-chrome.html`. A second adopting
plugin copies it byte-identical to the same path within its own root
(`reference/html-chrome.html`) and registers the cluster in
`scripts/cross-plugin-source-registry.txt` in the same change; the drift checker rejects
a registration while only one plugin carries the file, which is why the first adoption
ships unregistered by design. Skills cite the reference inline by role (their plugin's
own copy), never by a repository path an installed consumer cannot resolve.

## The `rendered-views` cascade concern

The cross-plugin output-format preference rides the
[config-cascade convention](../config-cascade/README.md); this section is the concern's
owner declaration.

- **Surface**: `.claude/rendered-views.md`, in all three layers (user-global
  `~/.claude/rendered-views.md`, team `.claude/rendered-views.md`, overlay
  `.claude/rendered-views.local.md`).
- **Keys** (per-key override, declared here per the contract): `medium` — one of `auto`,
  `terminal`, `file`, `artifact`; the preferred rung for rendered views, applied within
  reachability. Future keys are added here first.
- **No policy-floor class**: every key is a taste dial over deliverable presentation; a
  personal value weakens nothing another surface depends on (the `ai-slop` precedent).
  The default direction holds: the team layer refines user-global, the overlay is the
  operator's per-repo trump, and the user's global preference governs wherever no repo
  layer speaks.
- **Tier ladder across mechanisms**: explicit argument, then the plugin's own `userConfig`
  dial, then this cascade surface, then the shipped default. Plugin `userConfig` dials
  are never keys in this surface; a layer declaring one is reported as an inert unknown
  key (the `bugs` partition precedent).
- **Resolution**: per the contract's algorithm (anchor at the repo root, read every layer
  that exists, report which layer supplied each value, degrade soft and visibly on a
  malformed or absent layer).

## What this convention does not do

- It never makes HTML the record: the markdown record stays authoritative everywhere.
- It adds no generic HTML-generating skill: each skill owns its genre's page shape, and
  `visualization:visualize` stays a router that owns no craft.
- It does not migrate the grandfathered surfaces: that sweep is priced and tracked
  separately, gated on the userConfig smoke test.
