# Changelog

All notable changes to the `playbooks` plugin are recorded here. The `version` in
`.claude-plugin/plugin.json` is the delivery vehicle — a consumer receives a change
only after that version increases.

## [0.6.6]

### Added

- **`fable-5` verification gains the built-in verification surfaces table.**
  `skills/fable-5/context/verification.md` adds "Know what already verifies before you build a
  check", triggered when a project is about to get a custom check rather than a one-off probe. Six
  surfaces are mapped to their own reference pages, pointer-not-copy, and presented as **spanning
  three products** rather than one feature list — the harness (`/verify`, toolchain signals,
  project build and test commands in CLAUDE.md), a managed review service (Code Review), CI
  (a GitHub Actions job invoking Claude with a verification skill), and a separate platform API
  product (rubrics in Claude Managed Agents, whose grader runs in its own context window and hands
  failures back for rework). The two items with no harness artifact stay **rows** rather than being
  dropped to prose, because an item the source lists and nothing implements is the most useful
  thing the table records: spec validation — verifying each change against a markdown spec — is **a
  pattern, not a shipped artifact**, its Canonical-page cell says so and routes to the repo-local
  skill mechanism, and its absence ships as an as-of claim (checked 2026-08-03 against the
  bundled-skill rosters in [Skills](https://code.claude.com/docs/en/skills) and [Slash
  commands](https://code.claude.com/docs/en/commands)) with a recheck trigger on a release note
  adding one; and Managed Agents rubrics belong to **a different product**, so the in-session
  equivalent is a construction you assemble (a fresh-context subagent as grader) reached through
  the bundled `/claude-api managed-agents-onboard` skill. The section closes on **built-in never
  means automatic**: since v2.1.215 `/verify` and `/code-review` run only when invoked, and Code
  Review is research preview, limited to Team and Enterprise, unavailable under Zero Data
  Retention, and enabled per repository by an Owner
  ([Skills](https://code.claude.com/docs/en/skills#bundled-skills), [Code
  Review](https://code.claude.com/docs/en/code-review)). Every page in the table was re-fetched
  2026-08-03, HTTP 200.

- **`fable-5` calibration gains the channel-authority rule.**
  `skills/fable-5/context/calibration.md` adds "The reference page defines; a vendor post
  corroborates" — a **channel** axis distinct from the surface axis the neighbouring section owns:
  a vendor's own blog or launch post is first-party and still not the authority on what a term
  means, because it is written once and never revised while the page owning the term is maintained
  against the behavior it describes. The rule is cite-the-owning-page, pointer-never-copy, and
  read the page even when the post's definition looks complete, since omission is invisible from
  inside a summary. The worked instance ships with it: "verification loop" and "agentic loop" are
  owned by the [glossary](https://code.claude.com/docs/en/glossary), [How Claude Code
  works](https://code.claude.com/docs/en/how-claude-code-works), and [Best
  practices](https://code.claude.com/docs/en/best-practices), and the glossary entry carries what a
  post-length definition drops — a verification loop is the **prerequisite** for `/goal`,
  unattended runs, and dynamic workflows, so the short definition leaves a reader right about the
  concept and unaware that three capabilities depend on it (verified 2026-08-03).
  `skills/fable-5/SKILL.md` carries the distilled line under core doctrine, "Ground truth and
  checking — calibration".

### Changed

- **`fable-5` orchestration records the second rationale for decomposing.**
  `skills/fable-5/context/orchestration.md`, section "Decompose by context, not by headcount",
  previously justified decomposition on context economy alone. It now records **output
  consistency** beside it — a worker holding one focused subtask makes fewer inconsistency errors
  across scaled workflows than one holding the whole job ([Increase output
  consistency](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/increase-consistency),
  verified 2026-08-03) — with the operational consequence stated as a tiebreak: a piece too small
  for context economy to justify the spawn can still be worth spawning for consistency across a
  large set. The rationale is deliberately **mechanism-agnostic** — subagent delegation, a dynamic
  workflow, and a `claude -p` fan-out all realize the same partition, and the choice belongs to the
  delegation decision, not to the reason for decomposing. Recorded in exactly one place: the
  planning and context-economy chapters already route delegation to that chapter rather than
  restating it, and no distilled line is added, so the rationale has one home rather than two.

## [0.6.5]

### Changed

- **`fable-5`'s per-model adaptation chapters move out of the skill to plugin level.**
  `skills/fable-5/context/model-adaptation/{opus-4-8,opus-5}.md` become
  `reference/model-adaptation/{opus-4-8,opus-5}.md`; chapter contents are unchanged. Two forces
  drove it. The old host was named after a model with **zero** chapters in it — the directory's
  entire contents are deltas for *other* models, because Fable-5 doctrine is the skill's twelve
  `context/` chapters and the adaptation directory exists for models that are not Fable 5. And the
  old address sat inside a skill's private surface as `docs-hygiene:audit-encapsulation` defines it
  (any path into a subdirectory under a skill other than `scripts/`), so every consumer citing a
  chapter committed a **fresh** violation, one per consumer, with duplication — forbidden by this
  repository's documentation doctrine — as the only alternative. A plugin-root directory is not
  inside any skill, so the private-surface rule does not engage at the new address; the derivation
  is that the rule does not reach plugin-level directories, **not** that the contract declares them
  public. The shape is precedented in-repo by `plugins/autonomy/reference/` and
  `plugins/architecture/reference/`, and mints no new skill, so the shared skill-listing budget is
  unaffected. Recorded as
  [ADR-0007](../../docs/adr/0007-host-per-model-doctrine-outside-skill-private-surfaces.md),
  superseding ADR-0006 **on the seam's address and nothing else** — ADR-0006's decision (model-scoped
  by default, fleet-wide only through the promotion gate, routing by version and never by family) is
  preserved verbatim. ADR-0007 cures **one of ADR-0006's three** live private-surface cites; the two
  reaching `audit-instructions` and `docpage-digest` survive untouched and belong to other skills.
- **`fable-5`'s `SKILL.md` re-points five references at the new host** — four carrying the new
  address (one of those, the `full` argument's clause, also rewritten semantically) and one, the
  routing table's preamble, carrying no address at all. Meta-rule 3 (the arm-time mandatory read), the chapter-routing table's last
  row, and the "not model-version documentation" scope fence now name
  `${CLAUDE_PLUGIN_ROOT}/reference/model-adaptation/`. The `full` argument's clause is **rewritten
  rather than re-addressed**: it previously read every file under `context/` *except*
  `context/model-adaptation/`, an exclusion with nothing left to exclude once the chapters leave
  `context/`. It now reads all of `context/` and takes from the new directory only the chapter
  meta-rule 3 selects, **never the directory as a whole** — preserving the fence that matters, since
  the sibling versions' chapters carry deliberately reversed counter-steers and loading two at once
  puts conflicting doctrine in one session. The routing table's preamble no longer claims all
  chapters live under `context/`.
- **`${CLAUDE_PLUGIN_ROOT}` interpolation inside a skill body is verified rather than assumed.**
  Upstream documents the substitution for hook commands, MCP and LSP server configuration, monitor
  commands, and `allowed-tools` frontmatter — **not** for prose body text, and meta-rule 3 is the one
  instruction firing unconditionally for every non-Fable model, so a silent non-resolution would be a
  no-read for the entire population the chapters serve. The claim therefore carries the four-part
  record. **Claim:** the harness substitutes `${CLAUDE_PLUGIN_ROOT}` in a `SKILL.md` body before the
  model receives it. **Basis:** two headless `claude -p` probes on Claude Code 2.1.220 — a disposable
  plugin loaded via `--plugin-dir` returned the token expanded to its plugin root and read the file at
  the expanded path successfully, and an already-installed user-scope plugin (`discipline` 0.10.1)
  returned a body line carrying both forms, with the token expanded and a relative path on the same
  line left literal, which distinguishes harness substitution from a model normalizing paths on its
  own. **As of:** 2026-08-03. **Recheck trigger:** any Claude Code upgrade, since body-text
  substitution is not a documented contract. The relative-path form used at
  `plugins/autonomy/skills/setup/templates/isolation-probe.md:6` remains the attested fallback.

Earlier entries in this file name the chapters at their former `context/model-adaptation/` address.
They record what shipped at the time and are correct as written.

## [0.6.4]

### Added

- **`fable-5` context economy gains the thinking-cost section.**
  `skills/fable-5/context/context-economy.md` adds "Your own thinking is context you pay for
  twice": thinking is billed as output when generated and again as input on every later request,
  and neither half is visible in what the session displays. Billing is invariant across the
  `display` setting — summarized and omitted bill identically and summary generation is free — so
  hiding thinking is never a cost lever ([Steering thinking:
  Pricing](https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost#pricing),
  verified 2026-08-03). The retention half is stated as a **harness override with its boundary
  conditions**, not as a flat truth: the per-model preservation split upstream documents (all turns
  on keep-all models, only the last turn elsewhere) is what a raw API caller gets, while Claude
  Code overrides it in the keep-all direction on every thinking-enabled request, so retained blocks
  accumulate and bill as input on every model. The section carries the four-part verification
  record that override requires — claim, basis (request bodies emitted by `claude.exe`,
  265,720,480 bytes, read for both a documented keep-all and a documented last-turn-only model,
  with `context-management-2025-06-27` present in each request's `betas`), as-of date, and a
  recheck trigger on any Claude Code upgrade, since `keep:"all"` is a build-time constant rather
  than a documented contract. The three gating conditions and the two escapes that resume the
  per-model default (`CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`, or a gateway dropping the field)
  are stated with it. The input-billing half is explicitly upstream's own rule for retained blocks
  ([Thinking and the context
  window](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-the-context-window))
  applied to that forced retention, not a second observation — the wire evidence proves retention,
  not billing. `skills/fable-5/SKILL.md` carries the distilled line under core doctrine, "Managing
  your window — context-economy". Both surfaces **bound the accumulation to the current uncompacted
  window**: `keep:"all"` preserves only blocks a request still carries, and compaction "replaces
  your message history with a summary" ([Compacting the
  conversation](https://code.claude.com/docs/en/prompt-caching#compacting-the-conversation),
  verified 2026-08-03), so thinking summarized away — or dropped by `/clear` or a rewind — is
  neither re-sent nor re-billed, and the count restarts at the last history reset rather than at the
  first turn. The four-part record is unaffected: `keep:"all"` is still what the harness sends, and
  only the billing scope downstream of it narrows.

### Changed

- **`fable-5` Opus 5 adaptation no longer defers effort claims to an unreachable target.**
  `skills/fable-5/context/model-adaptation/opus-5.md` routed every effort claim beyond its three
  quoted bullets to "the verified effort-doc slice (see this workstream's Phase 6 cross-check)" —
  both referents campaign-internal and resolvable by no consumer of this plugin, the same defect
  class refused in 0.6.3 for a routing note between `.work/` slice directories. The deferral now
  points at the live [Effort](https://platform.claude.com/docs/en/build-with-claude/effort) and
  [model config: adjust effort
  level](https://code.claude.com/docs/en/model-config#adjust-effort-level) pages (both fetched raw
  2026-08-03, HTTP 200), and names per-model starting level alongside the ladder items already
  listed as upstream-owned. The file's TRUNCATED finding about the guide's own ladder statement is
  preserved as the reason those three bullets are its whole effort content.

## [0.6.3]

### Added

- **`fable-5` calibration gains the product-surface scope rule.**
  `skills/fable-5/context/calibration.md` adds "A claim's product surface travels with it": a
  behavioral claim about Claude is a fact about the surface documenting it, and it transfers to the
  surface the session runs on only after a per-claim check — never on vendor authority alone. The
  rule is scoped to CROSS-surface transfer, which is the row's actual thesis: docs for the running
  surface clear the check where they stand, so Claude Code's own docs read inside Claude Code are
  not downgraded. A dated archive entry is scoped to its date on top of that. Two worked
  divergences carry it, both genuine published text from Anthropic's claude.ai system prompts and
  both false read as facts about this harness — "Claude does not retain information across chats"
  (Claude Opus 4.1 entry, dated August 5 2025) against Claude Code's two documented cross-session
  mechanisms, CLAUDE.md files and auto memory; and "Claude cannot open URLs, links, or videos"
  (Claude Sonnet 3.5 entry, dated November 22 2024) against the documented `WebFetch` tool. Both are
  stamped to their entry rather than stated in the present tense, because **neither sentence
  survives in a current entry** — wrong-surface and stale-entry are independent errors, and the
  staleness is the rule's second half rather than a defect in the example. Verified 2026-08-03
  against [published system prompts](https://platform.claude.com/docs/en/release-notes/system-prompts),
  [memory](https://code.claude.com/docs/en/memory), and
  [tools reference](https://code.claude.com/docs/en/tools-reference); recheck trigger: a new dated
  entry restores or reverses either sentence, or Claude Code's memory or tool surface changes.
  `skills/fable-5/SKILL.md` carries the distilled line under core doctrine, "Ground truth and
  checking — calibration", per the chapter/core-doctrine pairing the rest of that file follows.

## [0.6.2]

### Fixed

- **`boris` no longer contradicts this repo on `max` effort durability.**
  `skills/boris/SKILL.md`'s Quick Reference row read "max is session-only" flat, and
  `skills/boris/reference/autonomy.md` §72 read "Max applies only to current session. All other
  effort levels (including xhigh) are sticky" — while `docs/PLUGIN-PHILOSOPHY.md` carried the
  exception. Two statements of one actionable fact, disagreeing. `PLUGIN-PHILOSOPHY.md` is right,
  verified 2026-08-02 against
  [model config — adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level):
  "`max` provides the deepest reasoning and applies to the current session only, except when set
  through the `CLAUDE_CODE_EFFORT_LEVEL` environment variable", and for the persisted `effortLevel`
  setting, `max` and `ultracode` "are not accepted here". Both files now carry the exception. §72
  additionally records the two further limits on "sticky" that the same page states — a level set
  with `/effort` in non-interactive `-p` mode is session-only, and first-running Fable 5, Opus 4.8,
  or Opus 4.7 holds that model's default across sessions until an explicit choice (Opus 5 has no
  such hold) — as a conforming `docs/conventions/upstream-drift` record: claim, cited page, as-of
  date, and a divergence-at-fetch recheck trigger. `skills/boris/vendor/SKILL.md` carries the same
  claim and is deliberately **not** changed — it is the verbatim upstream baseline used for drift
  detection, so editing it would manufacture false drift.

- **`boris` benchmark figures now declare themselves launch-day snapshots and carry a recheck
  trigger.** `skills/boris/reference/orchestration.md` restated volatile scores — SWE-Bench Pro,
  Terminal-Bench 2.1, GDPval-AA, FrontierCode/Diamond, OSWorld-Verified — at §78 and §94 with no
  as-of date and no stated re-derivation event, so nothing told a reader they had aged past the
  releases they announced. Benchmark names, suite versions, and scores churn independently of the
  models they rank. A file-level four-part record now classifies the figures as historical and
  fires on a decision that would turn on any of them, a new frontier-model release, or a suite
  version bump. Both carrier lines are prefixed "Launch-day benchmarks" and now cite the basis the
  record claims for them — the vendor's own launch announcement, [Opus 4.8, May 28
  2026](https://www.anthropic.com/news/claude-opus-4-8#opus-48s-capabilities) and [Fable 5 /
  Mythos 5, Jun 9
  2026](https://www.anthropic.com/news/claude-fable-5-mythos-5#evaluating-claude-fable-5-and-claude-mythos-5).
  Both pages publish their figures in a capabilities-table **image**, never in page text, so the
  record says so: a re-checker who greps the fetched HTML finds nothing and would read a correct
  citation as broken. The figures themselves are
  unchanged — they are accurate for their releases, and refreshing them here would restate a fresh
  snapshot the record exists to avoid. `skills/boris/vendor/SKILL.md` carries the same figures and
  is deliberately not changed, for the drift-detection reason above.

### Changed

- **`fable-5` states the thinking-off × effort hazard as one checkable rule instead of two loose
  halves.** `context/model-adaptation/opus-5.md`'s thinking-controls section documented the
  effort-conditional 400 in one bullet and the harness thinking-disable surfaces — including the
  `MAX_THINKING_TOKENS=0` Fable 5 exception — in another, and never joined them. A third bullet now
  states the rule they imply: a configuration pairing a thinking-disable surface with `xhigh` or
  `max` effort on Opus 5 and later is a per-request 400 assembled from configuration alone, with
  both operands configuration literals, so it is findable by reading them. Stated at the
  strength the evidence supports — it records the *config-time* question as untested rather than
  claiming Claude Code guards the combination (the section's existing probe covers only an
  already-sent request), leaves upstream's "Claude Opus 5 onward" scope unexpanded, and repeats
  that `MAX_THINKING_TOKENS=0` is not a universal kill switch. Each enumerated surface is stated
  at the value it can actually carry — the persisted `effortLevel` setting takes `xhigh` but not
  `max` ([model config — set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level):
  `max` and `ultracode` "are not accepted here"), matching what §72 of `boris` records above — and
  the API disable literal is written the way upstream writes it, `thinking: {"type": "disabled"}`
  ([what's new in Opus 5 — disabling thinking requires effort `high` or
  below](https://platform.claude.com/docs/en/about-claude/models/whats-new-opus-5#disabling-thinking-requires-effort-high-or-below)),
  since a rule whose whole claim is that the hazard is readable off configuration literals cannot
  ship an invalid one as its example. Both re-verified 2026-08-02.

## [0.6.1]

### Fixed

- **`boris` no longer states subagent nesting depth as a fixed number.** The ceiling is a
  configurable platform setting that moved three times in seven weeks — a fixed, unchangeable
  five layers (CC 2.1.172–2.1.216), a default of one (2.1.217), then a configurable default of
  three (2.1.219) — so any bare number is stale by construction
  ([sub-agents](https://code.claude.com/docs/en/sub-agents), which now carries both the current
  default and that full version history). `skills/boris/SKILL.md`'s Quick Reference row carried a
  bare present-tense "depth=5 cap" and now leads with the authoring imperative — never author a
  tree needing a specific depth — and names `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`.
  `skills/boris/reference/orchestration.md` §91 keeps its dated "shipped Jun 9, 2026 … capped at
  depth=5 to start" claim — that is historically true — but now marks the cap as historical and
  adds the current-state guidance. Matches the numberless shape already used by
  `session-flow:orchestrate` and `discovery`'s agent briefs.
  `skills/boris/vendor/SKILL.md` carries the same claim in six places and is deliberately **not**
  changed — it is the verbatim upstream baseline used for drift detection, so editing it would
  manufacture false drift.

## [0.6.0]

Lands the Opus 5 model-adaptation refresh from the `opus-5-prompting-interview` workstream
(dual-verified corpus: Opus 5 prompting guide + system card).

### Added

- **`fable-5`: `context/model-adaptation/opus-5.md`** — the Claude Opus 5 delta chapter: verified
  behavioral deltas (self-verification, scope, report-everything review, delegation floor, output
  length, effort posture), the architected-vs-instructed verification doctrine with its recorded
  residual tension, live-verified thinking controls including the session-observed
  thinking-off-above-`high` 400 (Claude Code does not clamp), an injection-robustness routing note
  with deferred-trigger, and pointer-only hard facts. Every claim carries a source citation and a
  Claude-Code-applicability tag.

### Changed

- **`fable-5`: model adaptation generalized to a per-version seam** — `context/opus-adaptation.md`
  moved to `context/model-adaptation/opus-4-8.md` (deltas unchanged; still calibrated for, and
  scoped to, Opus 4.8). `SKILL.md` meta-rule 3 now routes by model VERSION to
  `context/model-adaptation/<model>.md` and no longer tells any Opus model to apply the 4.8
  counter-steers verbatim — several are reversed by the Opus 5 guide (effort floor, per-edit-batch
  verifier dispatch, delegation bias, scope literalism). Routing-table row and "What this skill is
  NOT" pointer updated; `context/orchestration.md`'s chapter reference reworded to the
  model-neutral form.

## [0.5.2]

### Fixed

- **`boris` settings reference now points at the migrated documentation domain.** Anthropic moved
  the Claude Code docs from `docs.claude.com/en/docs/claude-code/<slug>` to
  `code.claude.com/docs/en/<slug>`; the settings link in `skills/boris/reference/autonomy.md`
  still used the old host and survived only on a 301. Verified by fetching the old URL, observing
  the 301, and confirming the target is the "Claude Code settings" page.
  `skills/boris/vendor/SKILL.md` carries the same stale URL and is deliberately **not** changed —
  it is the verbatim upstream baseline used for drift detection, so editing it would manufacture
  false drift.

## [0.5.1]

Runs the context-engineering rightsizing effort's criteria catalog
(`docs/topics/context-engineering-rightsizing/design/` on `feat/context-engineering-rightsizing`,
not yet merged to `main`) over `fable-5`, the one subtree decision D-6 excluded from the original
pass because #1261 was rewriting it concurrently. #1261 merged first; this closes the follow-up
(#1324).

### Changed

- **`fable-5`: narrow the fresh-context-verifier trigger to exclude mechanical,
  behavior-preserving batches** — `context/orchestration.md`, section "Fresh-context
  verification" (the owning site, full reasoning); `SKILL.md`'s core-doctrine distillation,
  `context/verification.md`'s floor statement, the owning section's own floor sentence, and
  `context/opus-adaptation.md`'s delegation correction all restate the trigger operatively and are
  narrowed to match, each pointing back to the owning section for the exception's detail.
  Previously the trigger fired unconditionally after any multi-file edit batch or before any
  multi-part completion claim; the catalog's S3 digest names this exact blanket dispatch as the
  D-5 target ("drop blanket dispatch on mechanical behavior-preserving work; keep it where the
  verdict is subjective or blast radius is wide") and lists `playbooks/fable-5` among the affected
  files. The carve-out reuses the planning chapter's existing behavior-preserving/behavior-changing
  distinction rather than inventing a second one, and a subjective verdict or a wide blast radius
  keeps the original trigger unchanged at all three sites.

## [0.5.0]

Numbered `0.5.0` rather than the `0.4.0` this branch first claimed: #1261 merged
first and took that number. The tier is unchanged — still **minor**, now measured
from `0.4.0` instead of `0.3.2`.

### Added

- **`boris`: four reference buckets for the twenty sections upstream added since
  the last sync** — [`unknowns.md`](skills/boris/reference/unknowns.md)
  (96–99, finding your unknowns), [`loops.md`](skills/boris/reference/loops.md)
  (100–103, the four loop types),
  [`automation.md`](skills/boris/reference/automation.md) (104–109, `/checkup`
  and automation as infrastructure), and
  [`context-engineering.md`](skills/boris/reference/context-engineering.md)
  (110–115, the Claude 5 context-engineering rules and Opus 5). Buckets follow
  upstream's own thread grouping — Parts 18, 19, 20–21, and 22.

### Changed

- **`boris`: vendored baseline synced 8.8.1 → 8.13.0** through
  `/playbooks:update --apply`, never a hand-copy. The delta is additive:
  sections 1–95 are unchanged, and the counts move 107 → 127 tips across
  95 → 115 sections. The hub's hardcoded counts (frontmatter description and
  body), the Topic Index, the Quick Reference, the source-date footer, and the
  plugin README's pack row all move with them.

## [0.4.0]

### Added

- `fable-5`: a show-moves section in the problem-framing chapter, split out of the
  unknown-knowns cell so the two signals that gate it — a criterion judgable only on
  sight, and a description costlier than an example — trigger those moves without firing
  the whole four-cell pass. It owns the evaluation-capacity precondition (candidates
  settle nothing when neither party can name what a strong one looks like), the exemplar
  hunt with its fidelity/cross-language/ask-ordering rules, the read-only reference-tree
  radius, and the elicitation artifact's distinct completeness bar.
- `fable-5`: a post-delivery attribution section in the problem-framing chapter — a
  deliverable returned as *not what was meant* re-runs the quadrant pass before it
  re-executes. Scoped away from observed defects, which keep routing to the debugging
  chapter's reproduction-first rule.
- `fable-5`: a durable-plan presentation rule in the planning chapter — decisions the
  reader would plausibly veto lead, ranked by the rework a late veto costs, as a second
  view that never re-sorts the risk-ordered steps.
- `fable-5`: the context-economy chapter gains a phase-boundary reset (every other reset
  trigger keys on loss or degradation, none on success), the note's decision content, and
  the note's disposition at task end so the debris sweep has an answer.
- `fable-5`: the communication chapter gains the offer-the-round rule for a large question
  residue, a volunteer question closing that round, a second trigger site for the
  evaluation-capacity gate, and a closing message that must name behavior which changed in
  code the diff does not show.
- `fable-5`: the show-moves section licenses a deliberately divergent spread — several
  directions differing along the dimension the user cannot put words to — as the
  extraction instrument when the criterion is recognition-only, handed over for them to
  react to rather than as an option survey owing a pick.

### Changed

- `fable-5`: the recommend-an-option rule and the attach-a-recommended-answer rule are both
  narrowed at their own sites: neither fires when the options exist to elicit the ranking
  criterion itself, because naming a favourite front-loads the judgment being asked for.
  The carve-out is defined by the missing criterion, not by a missing preference, and
  resolves without loading another chapter — trigger-gated loading means the communication
  chapter is often the only one held.

- `fable-5`: `SKILL.md` stated three of the problem-framing chapter trigger's four arms,
  in both the core-doctrine line and the routing table — the because-clause arm never
  fired from the always-loaded surface. Both now carry all four.
- `fable-5`: the problem-framing preamble owns the two priors the chapter's moves rest on
  — discovery priced against the rework it prevents, rising with what is already built on
  the unknown; and requests carrying unknowns they do not name. The clauses that
  previously re-derived the economics now cite it.
- `fable-5`: ambiguity residue is ordered by downstream work invalidated rather than by
  how widely its readings diverge; feasibility-shaped unknowns route to the planning
  chapter instead of a sort that has no branch for them; the blind-spot checklist reads as
  the software instance of a general move; an undisclosed starting point is asked for when
  it would change the pass width; and the scope bound is tested in both directions.
- `fable-5`: the long-horizon-memory bullet in the model-adaptation chapter now points at
  the context-economy chapter like its five siblings, instead of carrying general doctrine
  that had no owner elsewhere. The note-granularity and delete-when-disproved rules it used
  to carry land in the context-economy chapter, which now owns them.
- `fable-5`: the execution chapter's debris sweep carries one exemption — an artifact built
  to elicit a preference is not debris while the question it exists to surface is open. It
  is stated at the sweep itself, so an agent holding only that chapter honors it; the
  problem-framing chapter cites rather than restates it.

## [0.3.2]

### Changed

- `fable-5`: the fresh-context verification chapter now names the presence-gated
  cross-vendor advisor (e.g. the OpenAI Codex plugin, invoked per its own docs) with the
  fresh-context same-vendor subagent as the stated fallback — aligning the chapter's
  existing independence-gradient sentence to the seam-phrasing gate-plus-fallback shape,
  not adding a duplicate site. The gate lives at the orchestration chapter's
  "Fresh-context verification" SSOT; SKILL.md and the verification chapter keep their
  pointers.

## [0.3.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.0]

### Added

- **`skill-authoring` — precomputed-context authoring guidance.** New locally-owned spoke
  `reference/precompute-context.md` (not upstream) plus a hub pointer: when to inline deterministic,
  read-only context at load time via `!`command`` / ```! dynamic-context injection instead of a
  per-invocation tool call, and the two conventions we pin — a mandatory `|| echo "<fallback>"`
  defensive form (because the skills docs do not yet document `!` failure/timeout/stderr semantics)
  and `shell:`/Windows-host awareness. Both carry the recheck trigger: revisit if upstream documents
  `!` failure semantics. Points at the official `#inject-dynamic-context` docs for syntax rather than
  restating it. The vendored `vendor/SKILL.md` baseline is untouched.

## [0.2.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.0]

### Changed

- **BREAKING — skill renamed:** `thariq` → `skill-authoring` (`/playbooks:thariq` →
  `/playbooks:skill-authoring`). The pack's content is topic-shaped (skill authoring),
  so the skill is now named for what it teaches; the attribution to Thariq's post is
  unchanged in the skill body. No renames-map entry — consumers pick up the new name
  with this version. The upstream lane is unchanged: same upstream source URL, the
  vendored baseline (`vendor/SKILL.md`) is byte-identical, and `/playbooks:update`
  drift-check mechanics now point at the renamed pack path. Only the wrapper skill
  name (directory, frontmatter `name`, and references) changed.

## [0.1.0]

### Added

- **`playbooks` plugin** — merges three previously standalone knowledge/doctrine
  plugins into one, plus a central maintainer update skill:
  - `boris` (`/playbooks:boris`) — merged from the `boris` plugin's `boris` skill
    (formerly `/boris:boris`). Boris Cherny's Claude Code workflow tips, with its
    topic reference files, vendored upstream baseline, and update script carried over.
  - `thariq` (`/playbooks:thariq`) — merged from the `thariq-skills` plugin's
    `thariq-skills` skill (formerly `/thariq-skills:thariq-skills`). Anthropic's
    internal skill-authoring playbook, with its vendored upstream baseline and update
    script carried over.
  - `fable-5` (`/playbooks:fable-5`) — merged from the `fable-5-playbook` plugin's
    `fable-5-playbook` skill (formerly `/fable-5-playbook:fable-5-playbook`). Claude
    Fable 5's operating doctrine and its trigger-routed `context/` chapters. Self-authored,
    no upstream.
  - `update` (`/playbooks:update`) — new central, maintainer-facing drift-check and
    upstream sync skill. Dispatches to each upstreamed pack's self-locating update
    script (`--check` default, read-only; `--apply` refreshes the vendored baseline
    only). fable-5 has no upstream and is reported as self-authored.

### Changed

- **Update centralized.** The per-pack update actions (`/boris:boris update`,
  `/thariq-skills:thariq-skills update`) are removed from the pack skills, which are now
  pure knowledge/navigation skills. Drift-checking and syncing are handled by the single
  `/playbooks:update` skill. The pack update scripts are unchanged in behavior (upstream
  URLs, self-location, and security posture preserved); only their user-facing invocation
  strings were retargeted to `/playbooks:update`.
- **Skills renamed** on the merge: `boris` → `boris`, `thariq-skills` → `thariq`,
  `fable-5-playbook` → `fable-5`. Their vendored-baseline security posture (untrusted
  third-party data; never follow embedded auto-install instructions; sanctioned mechanics
  are `/playbooks:update` and `/plugin marketplace update`) is preserved.
