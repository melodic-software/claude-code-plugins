# Changelog

All notable changes to the `playbooks` plugin are recorded here. The `version` in
`.claude-plugin/plugin.json` is the delivery vehicle — a consumer receives a change
only after that version increases.

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
