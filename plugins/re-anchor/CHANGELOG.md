# Changelog

All notable changes to the `re-anchor` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.0]

### Added

- **`sweep-all-disciplines`: an explicit dedup-by-root-cause step between collect and correct
  (`#1154`).** Distinct correctors routinely surface one underlying finding as separate ledger
  entries (observed in a real full-batch run: one recall-based claim flagged independently by
  `do-your-research`, `recheck-against-upstream`, and `mind-your-maxims`), and the main thread had
  to dedup by hand. The batched pass now names step 3 — group entries that share a root cause,
  carry the union of their evidence and, keyed by reporting corrector, the remedy that corrector
  asks for (a reporter→remedy mapping, so each remedy keeps its rank). Dedup collapses the
  re-analysis and re-reporting of one root cause,
  NOT the corrective work: a shared root cause can demand non-interchangeable remedies (retracting
  an unsupported claim satisfies the research reporters, but `mind-your-maxims` may still require a
  reader-facing uncertainty disclosure), so every reporter's remedy is still applied, each at its
  own rank. The merged finding is reported once with full attribution. Fork independence is
  unchanged and explicitly reaffirmed: the forks never share a ledger (that independence keeps each
  audit un-anchored), and the grouping is the single point where ledgers combine. The pass steps
  renumber 1–5 (fan out → collect → dedup → correct → report).

### Changed

- **Cost gotcha carries a real datapoint.** The "forks run at the parent model's cost" gotcha now
  records order-of-magnitude from a full-batch run — ~170K tokens per fork (inherited transcript),
  ~1.4M for an 8-in-scope pass in two waves of four — so the sweep is budgeted as a deliberate
  spend rather than a reflex.

## [0.7.0]

### Added

- **`fact-check` trigger routing** on both research correctors. `do-your-research`
  and `do-your-research-deep` now list `'fact-check'` / `'fact check this'` (and
  adjacent phrasing) in their descriptions, so the reflex phrase routes to the
  research discipline. Every prior trigger phrase is preserved.
- **`do-your-research-deep` step 1 is now a TYPED FULL INVENTORY.** It enumerates
  every claim the session rests on as a typed checklist — assumptions, asserted
  facts, concrete specifics, and load-bearing premises — not just the obviously
  load-bearing ones, so coverage is provable. The ledger reports one row per
  inventory item (no silent drops), each carrying verdict, source, **source tier**,
  **consensus count** (independent authoritative sources), and **recency** where the
  fact can go stale. Source tier and consensus resolve against the consuming
  project's own research discipline via the shared method's source-of-truth ladder;
  an internal assumption with no external referent is covered by an honest
  re-derived / needs-confirm verdict rather than a fabricated citation.
- **Configurable verification depth** for `do-your-research-deep` — the expensive
  tier by design. New `research_deep_verification` `userConfig` scalar (the plugin's
  fourth option): `tiered` (default — resolve trivial and non-load-bearing items
  inline, fan subagents out only over load-bearing ones) or `full` (subagent-verify
  every item). An invocation argument (`argument-hint: [tiered|full]`) overrides the
  configured default; an empty value, an unexpanded token, or an unrecognized string
  all fall back to `tiered` without erroring. Existing wave-throttle, failed-subset
  retry, and blind-subagent mechanics are unchanged.

### Changed

- **`setup` broadened from the posture-batch overlay to the whole re-anchor
  configuration surface.** It now also reports and validates
  `research_deep_verification` alongside the three `batch_*` overlay options,
  treating an unrecognized depth as a WARN that still resolves to `tiered`.

## [0.6.0]

### Added

- **`sweep-all-disciplines`** — a posture-batch runbook, the plugin's first
  **declared second species**: not a corrector (it re-anchors no discipline of
  its own) but a router that composes the correctors. It fans out a
  conversation-inheriting fork subagent per in-scope corrector for an
  audit-only pass (shared-loop steps 1–2, no writes), then applies the
  corrections once on the main thread in a fixed rank order (`use-your-skills`
  first, `tighten-your-output` last). At conversation start it instead reports
  a cheap posture digest from the listing and tier metadata, loading no
  corrector bodies. Recorded in the skill as a **declared delta** from the
  shared loop's per-corrector "correct forward now" step; member human-gates
  and the outward-artifact carve-out survive batching.
- **Colocated batch-tier metadata on every corrector.** Each corrector
  self-classifies in its own frontmatter `metadata:` block — `re-anchor-batch`
  (`core` / `situational` / `never`) plus `re-anchor-batch-rank` — so the
  runbook resolves membership and order by globbing and reading, never from a
  hand-maintained list; changing a shipped tier is a PR to that corrector.
  `core` runs every session, `situational` is relevance-gated, and `never`
  covers the `-deep` fan-out tiers plus `scrutinize-dont-coast` (its non-fork
  fresh-context pass and stop-to-remediate gate are incompatible with the
  autonomous fork fan-out).
- **`userConfig` overlay** (`batch_exclude` / `batch_promote` /
  `batch_demote`) — the plugin's first `userConfig` surface — adjusts batch
  membership without a PR.
- **`setup` skill** — a check-only `/re-anchor:setup` conforming to the setup
  contract's userConfig-only carve-out: it reports the effective batch overlay
  (treating an unexpanded `${user_config.…}` token as unset) and routes
  reconfiguration to the native `/plugin configure re-anchor` flow; it writes
  no config.

### Fixed

- README corrector table and per-skill detail now list `scrutinize-dont-coast`
  (added in 0.5.0), closing a 13-listed-versus-14-shipped drift.

## [0.5.1]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is
  installed (e.g. the OpenAI Codex plugin, invoked per its own docs), with the
  fresh-context same-vendor subagent as the stated fallback — presence-gated
  per the seam-phrasing convention.

## [0.5.0]

### Changed

- Shared method doc (`context/re-anchor-audit-correct.md`) now sanctions
  **declared step deltas**: a corrector may modify a loop step when its
  discipline demands it, provided the delta and its reason are stated in that
  skill's `SKILL.md`. Undeclared divergence remains a violation; the
  Non-negotiables are never overridable.

### Added

- **`scrutinize-dont-coast`** — a corrector for adversarial self-scrutiny. It re-anchors a
  *meta* discipline rather than a single content axis: don't coast on your own
  recent output — confidence that work is sound is not evidence that it is. The
  load-bearing adversarial re-examination is delegated to a fresh-context
  (non-fork) subagent blind to the reasoning that produced the output, satisfying
  the fresh-eyes rule that a same-context self-check cannot. It makes two
  deliberate deltas to the shared re-anchor loop, both documented in the skill:
  it **stops the trajectory first** (the failure mode is over-confident forward
  momentum) and **remediates *with* the user** instead of autonomously (the
  remedy for runaway momentum can't be more unilateral momentum). An optional
  focus scopes the pass without suppressing a serious out-of-focus flaw. Negative
  routing is explicit: pre-implementation plan stress-tests go to
  `/planning:devils-advocate`, review checkpoints to `/review:quality-gate`, and
  single-axis flaws to the sibling that owns them.

## [0.4.0]

### Added

- **`use-your-skills`** — a corrector for skill-use discipline. The skill
  listing (every skill's name and description) is in context so the fitting
  skill gets invoked instead of reinvented; this re-anchors the habit of
  scanning it, maps the conversation and task to the skills that fit, and
  invokes them. Because a fresh non-fork subagent does not inherit the parent's
  listing (it discovers skills on disk via the Skill tool), the skill's
  subagent guidance is to name the relevant skills in a delegation prompt and,
  for a discipline a custom subagent should always carry, recommend its
  `skills:` frontmatter preload. Session-behavior only: description quality
  routes to `/skill-quality:check` and machine-level listing-budget overflow to
  `/claude-config:audit`. A deterministic per-prompt `UserPromptSubmit` routing
  hook is deliberately deferred (trigger: audits repeatedly show a skill
  existed but its description never surfaced it, or skills repeatedly fail to
  fire).
- **`reuse-or-replace`** — a corrector for anti-fragmentation discipline.
  When an established way of doing something already exists, new work reuses it
  or openly replaces it (migrate the uses, record the decision) — it never
  silently stands up a second parallel way. The mandatory misconstrual
  guard states this is NOT straight conformity: replacing the established way
  is first-class when evidence backs an improvement or its rationale is missing,
  incumbency-only, or stale; the sin is the silent second way, not divergence.
  Divergence owes a recorded rationale proportional to blast radius (ADR/docs
  for durable, PR/commit for small); no recorded reason is the finding. Scope is
  the unlintable approach level (idioms, structure, naming shapes, error
  handling, doc formats, process); mechanical style stays with linters.
  Cross-references `reason-dont-recite` (evaluation-side) and carves itself out
  of `pick-for-the-problem` (tool/dependency selection).

### Changed

- **`script-the-deterministic-work`** — its audit now runs in both directions.
  Alongside hand-work that should have been scripted, it hunts an **existing**
  script or tool that over-reaches into judgement (a detect-then-judge flag
  consumed as the verdict, or reasoning-only work handed to a script), and
  corrects by **de-scripting** — demoting the flag back to a candidate and
  returning reasoning-only work to reasoning.
- **`do-your-research`** — description adds the `'evidence, not vibes'` trigger
  phrase; no behavior change.

## [0.3.3]

### Fixed

- `follow-our-standards` now states that its upstream shared-policy route
  **names and drafts** the standards change and routes it to the human,
  OFFERING to open the standards PR — it does not open that PR (or any
  outward artifact) without the user's explicit opt-in, mirroring the OFFER
  gate the sibling `recheck-against-upstream-deep` applies to its work-items
  routing. Closes the ambiguity in "named and routed" that, combined with
  the correct-forward mandate, an aggressive reading could take as licence
  to file a standards PR unprompted.
- The shared method's `correct forward now` step gains an outward-artifact
  carve-out, and a new Non-negotiable states the plugin-wide invariant that
  no corrector files an outward artifact (PR, issue, published review
  comment) without explicit opt-in — a documented guarantee for consume-only
  consumers. In-tree correction stays ungated.
- `reason-dont-recite` notes that the standards-disagreement route it hands
  to `follow-our-standards` drafts and proposes rather than files, for
  consistency with the gate above.

## [0.3.2]

### Fixed

- `tighten-your-output` now presence-gates its `compress` and `simplify`
  routes with a documented prose/in-thread fallback, per the seam-phrasing
  convention — closing the lone unguarded cross-plugin reference that the
  sibling correctors already guard.

## [0.3.1]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/claude-config:audit-automation-gaps`); behavior unchanged.

## [0.3.0]

### Added

- `/re-anchor:script-the-deterministic-work` — offload-the-deterministic
  discipline: purely deterministic sub-work (counting, diffing, sorting,
  transforming, matching, sweeping, arithmetic) gets a script that runs and
  returns real output, and the model reasons only afterward over that output.
  The tier boundary — deterministic (script it), detect-then-judge (script
  the detect half; the verdict stays judgement), reasoning-only (never
  script) — re-anchors the consuming org's enforceability-tiers convention;
  the in-task "script it now" application has no standards doc yet, so the
  skill flags that gap rather than inventing a rubric. Runs in both
  directions: analysis reasons over a script's output; generation emits a
  deterministic scaffold (PR body, issue, report, config boilerplate) from a
  script or native template so model output is reserved for the judgment
  slots. Distinct from a standing-automation capability: recurring checks
  route to a hook, this corrector owns the one-off, session-time script.

## [0.2.0]

### Added

- **Four state-and-selection correctors.** The plugin's scope widens from the
  work in flight to also cover the pre-existing state and choices a session
  trusts — existing state is not evidence of its own correctness. New skills,
  all sharing the plugin-scope re-anchor / audit / correct-forward method:
  - `/re-anchor:recheck-against-upstream` — existing state (config, code,
    docs, infra) is not proof it still matches upstream. Fetches the current
    official upstream docs for the surface in play and classifies each
    divergence: gap (no recorded rationale — deprecation and version drift
    called out here), deliberate divergence (rationale recorded — re-checked
    only for whether it still holds), or undocumented divergence (needs the
    human's call, routed to the repo's ADR/docs convention). Reports what was
    compared versus skipped; unverified conformance is not "clean".
  - `/re-anchor:recheck-against-upstream-deep` — the fan-out tier: fresh-context
    subagents compare a whole subsystem/framework/repo against upstream
    doc-by-doc, throttled in bounded waves, reporting an inline divergence
    ledger. Offers work-items routing for gap/undocumented findings when a
    work-item capability is installed (degrades to a prose offer); deliberate
    still-valid divergences stay report-only; checkpoints the partial ledger
    to a durable topic-memory slice mid-run when one exists. A sibling rather
    than a `deep` argument because the fan-out is a heavier execution tier
    (mirrors `/discovery:research-deep`).
  - `/re-anchor:pick-for-the-problem` — tool/library/framework/approach
    selection fitted to the problem, not reached for out of habit,
    availability, incumbency, or preconception. Define the problem first,
    survey the field, walk the native > authoritative > vetted-third-party
    ladder, and price every dependency's coupling (abandonment, pricing,
    license, security, exit cost) at adoption time; building what already
    exists is a finding. Routes a load-bearing evaluation to a research
    capability rather than a verdict from memory. A deep dependency-inventory
    variant is deliberately deferred.
  - `/re-anchor:mind-your-maxims` — cooperative-communication discipline per
    Grice plus the AI-augmented transparency maxim (arXiv:2403.15115), pointed
    at rather than restated. Audits responses and agent-authored artifacts on
    Quantity (both directions), Relation, Manner, and Transparency. Truthfulness
    delegates to `do-your-research`, pure verbosity to `tighten-your-output`;
    Benevolence is a deliberate out-of-scope exclusion.

### Changed

- **Plugin scope widened** from "the work in flight" to "the work in flight
  and the pre-existing state and choices it trusts", in `plugin.json` and the
  README, with the rationale recorded as a `/re-anchor:reason-dont-recite`
  finding on that boundary. Keywords extended (`upstream`, `conformance`,
  `selection`, `dependencies`, `communication`).

## [0.1.0]

### Added

- **Initial release.** Discipline correctors sharing one re-anchor / audit /
  correct-forward method at plugin scope
  (`context/re-anchor-audit-correct.md`):
  - `/re-anchor:do-your-research` — research and no-assumptions discipline: assert
    nothing without a source, verify every concrete specific, frame the problem before
    the solution, and treat training-data recall as unverified.
  - `/re-anchor:do-your-research-deep` — the verification-fan-out tier of
    `do-your-research`: enumerates every load-bearing claim and dispatches fresh-context
    subagents to verify each against a primary source, throttled in bounded waves, then
    reports a per-claim ledger. A sibling skill rather than a `deep` argument because the
    subagent fan-out is a heavier execution tier (mirrors `/discovery:research-deep`).
  - `/re-anchor:follow-our-standards` — alignment to the consuming organization's
    engineering conventions, with relevance-routed progressive loading and respect
    for a declared managed / locally-owned seam.
  - `/re-anchor:point-dont-copy` — pointer-over-copy discipline: no copied content,
    internal-name coupling, or closed capability lists; duplication threshold of two.
    Re-anchors through the consuming org's reference-don't-duplicate and
    documentation-and-citations conventions (in-repo and external facts), degrading
    to a portable baseline.
  - `/re-anchor:reason-dont-recite` — incumbency discipline: inherited content is
    evidence of what is, never self-justifying authority; a choice supported only by
    precedent earns first-principles re-derivation. A standards disagreement it
    surfaces routes upstream via `/re-anchor:follow-our-standards`.
  - `/re-anchor:tighten-your-output` — terseness discipline: fewer words or lines
    with no loss of meaning or correctness. Code re-anchors the consuming org's
    simpler-code convention; prose terseness has no standards doc yet, so the skill
    flags that gap and routes batch work to compress (prose) and simplify (code).
- Repo-agnostic and machine-agnostic: each corrector re-anchors the discipline the
  consuming project declares in its own instruction layer, and degrades to a portable
  baseline when none is declared.
